import Foundation
import AVFoundation

public actor CosyVoiceTTSService: TTSServiceProtocol {
    public static let shared = CosyVoiceTTSService()
    
    private var serverReady = false
    public var isReady: Bool { serverReady }
    
    public func initialize() async throws {
        let url = URL(string: "http://localhost:8000/health")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                serverReady = false
                throw NSError(domain: "CosyVoiceTTSService", code: 503, userInfo: [NSLocalizedDescriptionKey: "CosyVoice Python bridge returned unhealthy status."])
            }
            serverReady = true
            print("CosyVoice Python Bridge is healthy and ready.")
        } catch {
            serverReady = false
            throw NSError(domain: "CosyVoiceTTSService", code: 503, userInfo: [NSLocalizedDescriptionKey: "CosyVoice Python bridge is offline. Please run the server in scripts/tts_engine."])
        }
    }
    
    public func synthesize(
        text: String,
        onAudioChunk: (@Sendable ([Float]) -> Void)? = nil
    ) async throws -> [Float] {
        // Find default savio.wav voice in Bundle resources or relative projects
        var refURL: URL? = Bundle.main.url(forResource: "savio", withExtension: "wav")
        if refURL == nil {
            let localFallback = "/Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox/PhonemeInferenceSandbox/VoiceResources/savio.wav"
            if FileManager.default.fileExists(atPath: localFallback) {
                refURL = URL(fileURLWithPath: localFallback)
            }
        }
        
        guard let finalRefURL = refURL else {
            throw NSError(domain: "CosyVoiceTTSService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Default reference voice (savio.wav) not found for synthesize."])
        }
        
        let (outputURL, _, _) = try await generateAudio(
            text: text,
            referenceAudioURL: finalRefURL,
            isMultiLanguage: false,
            language: "Auto",
            speed: 1.0
        )
        
        let floats = try loadFloats(from: outputURL)
        onAudioChunk?(floats)
        return floats
    }
    
    public func generateAudio(
        text: String,
        referenceAudioURL: URL?,
        isMultiLanguage: Bool = false,
        language: String = "Auto",
        speed: Float = 1.0
    ) async throws -> (URL, Double, Double) {
        
        let start = CFAbsoluteTimeGetCurrent()
        
        guard let refURL = referenceAudioURL else {
            throw TTSError.voiceNotFound("Reference audio is required for zero-shot cloning.")
        }
        
        let url = URL(string: "http://localhost:8000/generate/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Load reference audio data
        let audioData = try Data(contentsOf: refURL)
        
        var body = Data()
        
        // Add target_text
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target_text\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(text)\r\n".data(using: .utf8)!)
        
        // Add speed
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"speed\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(speed)\r\n".data(using: .utf8)!)
        
        // Add reference_audio file
        let filename = refURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"reference_audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "CosyVoiceTTSService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Server returned error: \(errorMsg)"])
        }
        
        let firstByteTime = CFAbsoluteTimeGetCurrent()
        let ttfa = firstByteTime - start
        
        // Save the output WAV file
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cosyvoice_output.wav")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try data.write(to: outputURL)
        
        // Determine audio duration to calculate RTF
        // Standard 24kHz, 16-bit mono PCM is 24000 * 2 = 48000 bytes/sec.
        // Size of data is data.count.
        // Header is 44 bytes.
        let duration = Double(max(0, data.count - 44)) / 48000.0
        let end = CFAbsoluteTimeGetCurrent()
        let rtf = (end - start) / max(0.001, duration)
        
        return (outputURL, ttfa, rtf)
    }
    
    public func stopAudio() async {
        // Since we are synchronous or not managing a streaming state yet, nothing to do here.
    }
    
    private func loadFloats(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let audioFrameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: audioFrameCount) else {
            throw NSError(domain: "CosyVoiceTTSService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate AVAudioPCMBuffer"])
        }
        try file.read(into: buffer)
        
        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "CosyVoiceTTSService", code: 500, userInfo: [NSLocalizedDescriptionKey: "No audio data found in WAV buffer"])
        }
        
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }
}
