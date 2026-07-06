import Foundation
import AVFoundation
import Combine
import NaturalLanguage
import Accelerate

class AudioRecordingService: NSObject, ObservableObject {
    
    // MARK: - Tempo Normalization
    
    static func normalizeTempo(audioURL: URL, targetScript: String, targetWPM: Double = 125.0) async throws -> URL {
        let file = try AVAudioFile(forReading: audioURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = targetScript
        var wordCount = 0
        tokenizer.enumerateTokens(in: targetScript.startIndex..<targetScript.endIndex) { _, _ in
            wordCount += 1
            return true
        }
        
        if wordCount == 0 || duration == 0 { return audioURL }
        
        let currentWPM = (Double(wordCount) / duration) * 60.0
        var targetRate = targetWPM / currentWPM
        
        targetRate = max(0.7, min(1.3, targetRate))
        
        if abs(targetRate - 1.0) < 0.05 {
            return audioURL
        }
        
        print("Normalizing Tempo: Current WPM: \(currentWPM), Target WPM: \(targetWPM). Applying rate: \(targetRate)")
        
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(targetRate)
        
        engine.attach(player)
        engine.attach(timePitch)
        
        let format = file.processingFormat
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        
        let outputURL = audioURL.deletingLastPathComponent().appendingPathComponent("user_speech_normalized_\(UUID().uuidString).wav")
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        
        player.scheduleFile(file, at: nil, completionHandler: nil)
        player.play()
        
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        let scaledLength = AVAudioFramePosition(Double(file.length) / Double(targetRate))
        
        while engine.manualRenderingSampleTime < scaledLength {
            let framesToRender = engine.manualRenderingMaximumFrameCount
            let status = try engine.renderOffline(framesToRender, to: buffer)
            switch status {
            case .success: try outputFile.write(from: buffer)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext: break
            case .error: throw NSError(domain: "AudioRecordingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline rendering failed"])
            @unknown default: break
            }
        }
        
        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        return outputURL
    }
    
    // MARK: - Preprocessing (Denoising & VAD & Loudness)
    
    static func trimSilenceAndDenoise(audioURL: URL) async throws -> URL {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return audioURL
        }
        try file.read(into: buffer)
        
        guard let channelData = buffer.floatChannelData else { return audioURL }
        let data = channelData.pointee
        let length = Int(buffer.frameLength)
        
        // 1. Voice Activity Detection (Trim Silence)
        var startIndex = 0
        let thresholdDB: Float = -50.0 // from PreprocessServices.swift config
        
        var peak: Float = 0
        vDSP_maxv(data, 1, &peak, vDSP_Length(length))
        
        let threshold = max(peak * pow(10, thresholdDB / 20), 0.015) // Fallback to 0.015 absolute if peak is very low
        
        let padStartFrames = Int(format.sampleRate * 0.05) // 50ms
        let padEndFrames = Int(format.sampleRate * 0.1) // 100ms
        
        for i in 0..<length {
            if abs(data[i]) > threshold {
                startIndex = max(0, i - padStartFrames)
                break
            }
        }
        
        var endIndex = length - 1
        for i in (0..<length).reversed() {
            if abs(data[i]) > threshold {
                endIndex = min(length - 1, i + padEndFrames)
                break
            }
        }
        
        if startIndex >= endIndex {
            return audioURL
        }
        
        let newFrameCount = AVAudioFrameCount(endIndex - startIndex)
        guard let newBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: newFrameCount) else {
            return audioURL
        }
        newBuffer.frameLength = newFrameCount
        
        for c in 0..<Int(format.channelCount) {
            let src = buffer.floatChannelData![c]
            let dst = newBuffer.floatChannelData![c]
            memcpy(dst, src.advanced(by: startIndex), Int(newFrameCount) * MemoryLayout<Float>.stride)
        }
        
        // 2. Loudness normalization (from PreprocessServices.swift targetLUFS = -18.0)
        let targetLUFS: Float = -18.0
        var meanSquare: Float = 0
        vDSP_measqv(newBuffer.floatChannelData![0], 1, &meanSquare, vDSP_Length(newFrameCount))
        if meanSquare > 1e-12 {
            let rmsDB = 10 * log10(meanSquare)
            let gainDB = targetLUFS - rmsDB
            var gain = pow(10, gainDB / 20)
            
            for c in 0..<Int(format.channelCount) {
                let channelData = newBuffer.floatChannelData![c]
                vDSP_vsmul(channelData, 1, &gain, channelData, 1, vDSP_Length(newFrameCount))
                
                var lowerBound: Float = -1
                var upperBound: Float = 1
                vDSP_vclip(channelData, 1, &lowerBound, &upperBound, channelData, 1, vDSP_Length(newFrameCount))
            }
        }
        
        // 3. Highpass Filter (Denoise) + write output
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        
        let filterParams = eq.bands[0]
        filterParams.filterType = .highPass
        filterParams.frequency = 80.0
        filterParams.bypass = false
        
        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        
        let outputURL = audioURL.deletingLastPathComponent().appendingPathComponent("baseline_preprocessed_\(UUID().uuidString).wav")
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        
        player.scheduleBuffer(newBuffer, at: nil, options: [], completionHandler: nil)
        player.play()
        
        let renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        
        while engine.manualRenderingSampleTime < newFrameCount {
            let framesToRender = min(engine.manualRenderingMaximumFrameCount, newFrameCount - AVAudioFrameCount(engine.manualRenderingSampleTime))
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            if status == .success {
                try outputFile.write(from: renderBuffer)
            } else {
                break
            }
        }
        
        // Pad end with 0.5s silence
        let padEndSeconds: Double = 0.5
        let paddingFrames = AVAudioFrameCount(padEndSeconds * format.sampleRate)
        if paddingFrames > 0 {
            if let silenceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: paddingFrames) {
                silenceBuffer.frameLength = paddingFrames
                for c in 0..<Int(format.channelCount) {
                    memset(silenceBuffer.floatChannelData![c], 0, Int(paddingFrames) * MemoryLayout<Float>.stride)
                }
                try outputFile.write(from: silenceBuffer)
            }
        }
        
        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        
        return outputURL
    }
}
