import Foundation
import AVFoundation

// MARK: - Supporting Types

/// Result returned from CosyVoice generation, including timing and pace metadata.
public struct CosyVoiceResult: Sendable {
    /// Local URL of the generated WAV file.
    public let audioURL: URL
    /// Time-to-first-audio (seconds).
    public let ttfa: Double
    /// Real-time factor (generation time / audio duration).
    public let rtf: Double
    /// Detected speech rate of the reference audio (words per minute).
    public let detectedWPM: Double?
    /// Pace normalization factor applied by the server.
    public let normFactor: Double?
    /// Effective playback speed sent to the TTS model.
    public let finalSpeed: Double?
}

// MARK: - Service

public actor CosyVoiceTTSService: TTSServiceProtocol {
    public static let shared = CosyVoiceTTSService()

    private var serverReady = false
    public var isReady: Bool { serverReady }

    // MARK: - TTSServiceProtocol

    public func initialize() async throws {
        let url = URL(string: "http://localhost:8000/health")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                serverReady = false
                throw NSError(
                    domain: "CosyVoiceTTSService", code: 503,
                    userInfo: [NSLocalizedDescriptionKey: "CosyVoice Python bridge returned unhealthy status."]
                )
            }
            serverReady = true
            print("CosyVoice Python Bridge is healthy and ready.")
        } catch {
            serverReady = false
            throw NSError(
                domain: "CosyVoiceTTSService", code: 503,
                userInfo: [NSLocalizedDescriptionKey: "CosyVoice Python bridge is offline. Please run the server in cosy_sandbox."]
            )
        }
    }

    public func synthesize(
        text: String,
        onAudioChunk: (@Sendable ([Float]) -> Void)? = nil
    ) async throws -> [Float] {
        var refURL: URL? = Bundle.main.url(forResource: "savio", withExtension: "wav")
        if refURL == nil {
            let localFallback = "/Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox/PhonemeInferenceSandbox/VoiceResources/savio.wav"
            if FileManager.default.fileExists(atPath: localFallback) {
                refURL = URL(fileURLWithPath: localFallback)
            }
        }

        guard let finalRefURL = refURL else {
            throw NSError(
                domain: "CosyVoiceTTSService", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Default reference voice (savio.wav) not found for synthesize."]
            )
        }

        let result = try await generateAudio(
            text: text,
            referenceAudioURL: finalRefURL,
            language: "auto",
            speed: 1.0,
            refLength: .short
        )

        let floats = try loadFloats(from: result.audioURL)
        onAudioChunk?(floats)
        return floats
    }

    // MARK: - Public API

    /// Generate speech from `text` using zero-shot voice cloning.
    ///
    /// - Parameters:
    ///   - text: The input text to synthesize.
    ///   - referenceAudioURL: URL of the reference WAV file to clone from.
    ///   - language: Backend language code — `"auto"` or `"chinese"`.
    ///   - speed: User-controlled pace multiplier (0.5 – 2.0).
    ///   - refLength: How much of the reference audio to upload. Trimming happens on device.
    /// - Returns: A `CosyVoiceResult` with the output URL, timing metrics, and pace metadata.
    public func generateAudio(
        text: String,
        referenceAudioURL: URL?,
        language: String = "auto",
        speed: Float = 1.0,
        refLength: TTSRefLength = .short
    ) async throws -> CosyVoiceResult {

        let start = CFAbsoluteTimeGetCurrent()

        guard let refURL = referenceAudioURL else {
            throw TTSError.voiceNotFound("Reference audio is required for zero-shot cloning.")
        }

        let maxSecs: Double
        switch refLength {
        case .short:  maxSecs = 5
        case .medium: maxSecs = 10
        case .long:   maxSecs = 15
        }
        let trimmedRefURL = try trimAudio(from: refURL, maxSeconds: maxSecs)
        defer { try? FileManager.default.removeItem(at: trimmedRefURL) }
        
        let transcribedText = try await SharedSTTService.shared.transcribe(audioURL: trimmedRefURL, maxSeconds: nil)

        let endpoint = URL(string: "http://localhost:8000/generate")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300 // TTS inference can take time

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: trimmedRefURL)

        var body = Data()
        appendFormField(to: &body, name: "text",            value: text,              boundary: boundary)
        appendFormField(to: &body, name: "speed",           value: String(speed),     boundary: boundary)
        appendFormField(to: &body, name: "target_language", value: language,          boundary: boundary)
        appendFormField(to: &body, name: "ref_text",        value: transcribedText,   boundary: boundary)

        // Binary reference audio upload
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
            throw NSError(
                domain: "CosyVoiceTTSService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Server error: \(errorMsg)"]
            )
        }

        let receivedTime = CFAbsoluteTimeGetCurrent()
        let ttfa = receivedTime - start

        // Parse pace metadata from custom response headers
        let detectedWPM  = httpResponse.value(forHTTPHeaderField: "X-Detected-WPM").flatMap(Double.init)
        let normFactor   = httpResponse.value(forHTTPHeaderField: "X-Norm-Factor").flatMap(Double.init)
        let finalSpeed   = httpResponse.value(forHTTPHeaderField: "X-Final-Speed").flatMap(Double.init)

        // Save the output WAV to a unique temp path
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosyvoice_output_\(UUID().uuidString).wav")
        try? FileManager.default.removeItem(at: outputURL)
        try data.write(to: outputURL)

        // Compute accurate audio duration via AVAudioFile for RTF
        let audioFile = try AVAudioFile(forReading: outputURL)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let end = CFAbsoluteTimeGetCurrent()
        let rtf = (end - start) / max(0.001, duration)

        return CosyVoiceResult(
            audioURL: outputURL,
            ttfa: ttfa,
            rtf: rtf,
            detectedWPM: detectedWPM,
            normFactor: normFactor,
            finalSpeed: finalSpeed
        )
    }

    public func stopAudio() async {
        // No streaming state to manage for synchronous HTTP generation.
    }

    // MARK: - Private Helpers

    /// Reads the first `maxSeconds` of audio from `url` and writes it to a temp WAV file.
    private func trimAudio(from url: URL, maxSeconds: Double) throws -> URL {
        let inputFile = try AVAudioFile(forReading: url)
        let format = inputFile.processingFormat
        let sampleRate = format.sampleRate

        let totalFrames = inputFile.length
        let maxFrames = AVAudioFrameCount(maxSeconds * sampleRate)
        let framesToRead = AVAudioFrameCount(min(Int64(maxFrames), totalFrames))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
            throw NSError(
                domain: "CosyVoiceTTSService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate buffer for audio trimming."]
            )
        }
        try inputFile.read(into: buffer, frameCount: framesToRead)

        // Find the last silence before the cutoff to avoid clipping mid-word
        let safeFrames = getSafeTrimFrame(buffer: buffer, maxFrames: framesToRead)
        buffer.frameLength = safeFrames

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosy_ref_\(UUID().uuidString).wav")

        let outputFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try outputFile.write(from: buffer)

        return tempURL
    }

    private func loadFloats(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let audioFrameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: audioFrameCount) else {
            throw NSError(
                domain: "CosyVoiceTTSService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate AVAudioPCMBuffer"]
            )
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(
                domain: "CosyVoiceTTSService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "No audio data found in WAV buffer"]
            )
        }
        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }

    /// Scans backwards in 100ms windows to find the last silent period (RMS < threshold).
    /// This prevents cutting mid-word which causes STT hallucinations.
    private func getSafeTrimFrame(buffer: AVAudioPCMBuffer, maxFrames: AVAudioFrameCount) -> AVAudioFrameCount {
        guard let channelData = buffer.floatChannelData?[0] else { return maxFrames }
        let sampleRate = buffer.format.sampleRate
        // Use a 300ms window to find a true pause, not just a stop-consonant closure (which can be ~100ms).
        let windowFrames = Int(0.3 * sampleRate)
        
        let minEnd = Int(Double(maxFrames) * 0.5)
        var currentEnd = Int(maxFrames)
        
        var bestEnd = Int(maxFrames)
        var bestRMS: Float = .greatestFiniteMagnitude
        
        while currentEnd - windowFrames >= minEnd {
            let start = currentEnd - windowFrames
            var sum: Float = 0.0
            for i in start..<currentEnd {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(windowFrames))
            
            if rms < 0.015 {
                return AVAudioFrameCount(currentEnd)
            }
            
            if rms < bestRMS {
                bestRMS = rms
                bestEnd = currentEnd
            }
            
            currentEnd -= Int(0.1 * sampleRate) // Step back by 100ms
        }
        return AVAudioFrameCount(bestEnd)
    }

    private nonisolated func appendFormField(to body: inout Data, name: String, value: String, boundary: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
}

