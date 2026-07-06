import AVFoundation
import CoreML
import Accelerate

class AudioService {
    static func loadAudio(from url: URL, targetSampleRate: Double = 16000.0) throws -> MLMultiArray {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let audioFrameCount = UInt32(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: audioFrameCount)!
        try file.read(into: buffer)
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
        
        let finalBuffer: AVAudioPCMBuffer
        if format != targetFormat {
            let converter = AVAudioConverter(from: format, to: targetFormat)!
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetSampleRate / format.sampleRate)
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)!
            
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
            if let error = error { throw error }
            finalBuffer = convertedBuffer
        } else {
            finalBuffer = buffer
        }
        
        let frameLength = Int(finalBuffer.frameLength)
        guard let channelData = finalBuffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data"])
        }
        
        let shape = [1, NSNumber(value: frameLength)]
        let multiArray = try MLMultiArray(shape: shape, dataType: .float32)
        
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(multiArray.dataPointer))
        
        // Wav2Vec2 requires zero mean and unit variance normalization
        var mean: Float = 0.0
        var stdDev: Float = 0.0
        vDSP_normalize(channelData, 1, ptr, 1, &mean, &stdDev, vDSP_Length(frameLength))
        
        if stdDev < 1e-7 || stdDev.isNaN {
            var zero: Float = 0.0
            vDSP_vfill(&zero, ptr, 1, vDSP_Length(frameLength))
        }
        
        return multiArray
    }
}

@MainActor
class AudioStreamPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double
    private let timePitch = AVAudioUnitTimePitch()
    private var isPlaying = false
    
    init(sampleRate: Double, useDSP: Bool = false, rate: Float = 1.0, pitch: Float = 0.0) {
        self.sampleRate = sampleRate
        engine.attach(player)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        
        if useDSP {
            engine.attach(timePitch)
            timePitch.rate = rate
            timePitch.pitch = pitch
            
            // Connect nodes: player -> timePitch -> mixer
            engine.connect(player, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        
        do {
            try engine.start()
            player.play()
            isPlaying = true
        } catch {
            print("Failed to start AVAudioEngine: \\(error)")
        }
    }
    
    func scheduleBuffer(_ floats: [Float]) {
        guard isPlaying else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(floats.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        let channelData = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            channelData[i] = floats[i]
        }
        
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
    
    func stop() {
        if isPlaying {
            player.stop()
            engine.stop()
            isPlaying = false
        }
    }
}
