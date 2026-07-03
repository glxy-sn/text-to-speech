import Foundation
import AVFoundation
import Combine
import NaturalLanguage

class AudioRecordingService: NSObject, ObservableObject {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    @Published var isRecording = false
    @Published var recordingURL: URL?
    
    func startRecording() async throws {
        #if os(macOS)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw NSError(domain: "AudioRecordingService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied."])
        }
        #else
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { result in
                continuation.resume(returning: result)
            }
        }
        guard granted else {
            throw NSError(domain: "AudioRecordingService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied."])
        }
        #endif
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        let audioFilename = docDir.appendingPathComponent("user_speech_raw.wav")
        
        let newEngine = AVAudioEngine()
        self.engine = newEngine
        
        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Save as 16kHz Mono Float32
        let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)!
        
        audioFile = try AVAudioFile(forWriting: audioFilename, settings: recordingFormat.settings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let audioFile = self.audioFile else { return }
            do {
                if buffer.format == recordingFormat {
                    try audioFile.write(from: buffer)
                } else {
                    // Convert buffer format if necessary
                    if let converter = AVAudioConverter(from: buffer.format, to: recordingFormat) {
                        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / buffer.format.sampleRate)
                        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: capacity) else { return }
                        var error: NSError?
                        var inputConsumed = false
                        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                            if inputConsumed {
                                outStatus.pointee = .endOfStream
                                return nil
                            }
                            inputConsumed = true
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        if error == nil {
                            try audioFile.write(from: convertedBuffer)
                        }
                    }
                }
            } catch {
                print("Error writing audio buffer: \(error)")
            }
        }
        
        try newEngine.start()
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingURL = nil
        }
    }
    
    func stopRecording() {
        guard let engine = engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        
        let url = audioFile?.url
        self.audioFile = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingURL = url
        }
    }
    
    // MARK: - Tempo Normalization
    
    static func normalizeTempo(audioURL: URL, targetScript: String, targetWPM: Double = 125.0) async throws -> URL {
        let file = try AVAudioFile(forReading: audioURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        
        // Count words using NaturalLanguage
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
        
        // Clamp rate to avoid extreme DSP artifacts
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
        
        let outputURL = audioURL.deletingLastPathComponent().appendingPathComponent("user_speech_normalized.wav")
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        
        try engine.start()
        player.scheduleFile(file, at: nil, completionHandler: nil)
        player.play()
        
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        
        // Calculate the expected scaled length
        let scaledLength = AVAudioFramePosition(Double(file.length) / Double(targetRate))
        
        while engine.manualRenderingSampleTime < scaledLength {
            let framesToRender = engine.manualRenderingMaximumFrameCount
            let status = try engine.renderOffline(framesToRender, to: buffer)
            
            switch status {
            case .success:
                try outputFile.write(from: buffer)
            case .insufficientDataFromInputNode:
                break
            case .cannotDoInCurrentContext:
                break
            case .error:
                throw NSError(domain: "AudioRecordingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline rendering failed"])
            @unknown default:
                break
            }
        }
        
        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        
        return outputURL
    }
    
    // MARK: - Preprocessing (Denoising & VAD)
    
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
        // Use a 0.01 amplitude threshold (~ -40dB) to trim silence
        let threshold: Float = 0.015 
        
        for i in 0..<length {
            if abs(data[i]) > threshold {
                // Keep 0.1s of padding
                startIndex = max(0, i - Int(format.sampleRate * 0.1))
                break
            }
        }
        
        var endIndex = length - 1
        for i in (0..<length).reversed() {
            if abs(data[i]) > threshold {
                endIndex = min(length - 1, i + Int(format.sampleRate * 0.1))
                break
            }
        }
        
        if startIndex >= endIndex {
            return audioURL // Fallback if audio is entirely quiet
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
        
        // 2. Highpass Filter (Denoise)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        
        // Highpass filter at 80Hz to remove rumble/hallucinated low-end noise
        let filterParams = eq.bands[0]
        filterParams.filterType = .highPass
        filterParams.frequency = 80.0
        filterParams.bypass = false
        
        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        
        let outputURL = audioURL.deletingLastPathComponent().appendingPathComponent("baseline_preprocessed.wav")
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        
        // Schedule the trimmed buffer
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
        
        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        
        return outputURL
    }
}
