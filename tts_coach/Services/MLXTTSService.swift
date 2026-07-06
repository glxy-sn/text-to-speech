import Foundation
import MLX
import MLXLMCommon
import MLXAudioCore
import MLXAudioTTS
import MLXAudioSTT
import AVFoundation

// MARK: - Constants

/// Using the Base model for zero-shot voice cloning.
private let kModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"

// MARK: - TTSService

/// A native Swift actor that manages the Qwen3-TTS model.
public actor QwenTTSService: TTSServiceProtocol {
    public static let shared = QwenTTSService()
    
    public var isReady: Bool { model != nil }

    private var model: SpeechGenerationModel?
    private var currentPlayer: AudioStreamPlayer?

    // MARK: - Public API
    
    // MARK: - TTSServiceProtocol Implementation
    
    public func initialize() async throws {
        _ = try await loadModelIfNeeded()
    }
    
    public func synthesize(
        text: String,
        onAudioChunk: (@Sendable ([Float]) -> Void)? = nil
    ) async throws -> [Float] {
        let model = try await loadModelIfNeeded()
        
        var safeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !safeText.hasSuffix(".") && !safeText.hasSuffix("!") && !safeText.hasSuffix("?") {
            safeText += "."
        }
        
        var allFloats = [Float]()
        let params = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.7,
            topP: 1.0,
            repetitionPenalty: 1.0,
            repetitionContextSize: 20
        )
        
        for try await event in model.generateStream(
            text: safeText,

            voice: nil,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: params
        ) {
            if case .audio(let chunk) = event {
                let floatArray = chunk.asArray(Float.self)
                allFloats.append(contentsOf: floatArray)
                onAudioChunk?(floatArray)
            }
        }
        
        return allFloats
    }

    // MARK: - Public API
    
    /// Generate speech audio using text-prompted voice design and streaming.
    public func generateAudio(
        text: String,
        referenceAudioURL: URL?,
        referenceTranscript: String? = nil,
        language: String = "Auto",
        speed: Float = 1.0,
        refLength: TTSRefLength = .short
    ) async throws -> (URL, Double, Double) {
        let model = try await loadModelIfNeeded()

        await currentPlayer?.stop()
        currentPlayer = nil

        var allFloats = [Float]()

        var safeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !safeText.hasSuffix(".") && !safeText.hasSuffix("!") && !safeText.hasSuffix("?") {
            safeText += "."
        }

        let params = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.7,
            topP: 1.0,
            repetitionPenalty: 1.0,
            repetitionContextSize: 20
        )

        var refAudioArray: MLXArray? = nil
        var refText: String? = nil
        if let refURL = referenceAudioURL {
            let (_, audioArray) = try loadAudioArray(from: refURL, sampleRate: model.sampleRate)
            refAudioArray = audioArray
            
            if let stored = referenceTranscript, !stored.isEmpty {
                print("Using known transcript directly...")
                refText = stored
            } else {
                print("Transcribing reference audio locally via Whisper...")
                refText = try await SharedSTTService.shared.transcribe(audioURL: refURL, maxSeconds: nil)
            }
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let targetLanguage = language == "Auto" ? nil : language
        let mlxArray = try await model.generate(
            text: safeText,
            voice: nil,
            refAudio: refAudioArray,
            refText: refText,
            language: targetLanguage,
            generationParameters: params
        )
        MLX.eval(mlxArray)
        allFloats = mlxArray.asArray(Float.self)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let ttfa = endTime - startTime
        let audioDuration = Double(allFloats.count) / Double(model.sampleRate)
        let rtf = (endTime - startTime) / max(audioDuration, 0.001)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native_baseline.wav")

        try AudioUtils.writeWavFile(samples: allFloats, sampleRate: Double(model.sampleRate), fileURL: outputURL)

        return (outputURL, ttfa, rtf)
    }
    
    public func stopAudio() async {
        await currentPlayer?.stop()
    }

    private func loadModelIfNeeded() async throws -> SpeechGenerationModel {
        if let model { return model }
        let loaded = try await TTS.loadModel(modelRepo: kModelRepo)
        model = loaded
        return loaded
    }
    
    // MARK: - Audio Trimming
    
    private func trimAudio(from url: URL, maxSeconds: Double) throws -> URL {
        let inputFile = try AVAudioFile(forReading: url)
        let format = inputFile.processingFormat
        let sampleRate = format.sampleRate

        let totalFrames = inputFile.length
        let maxFrames = AVAudioFrameCount(maxSeconds * sampleRate)
        let framesToRead = AVAudioFrameCount(min(Int64(maxFrames), totalFrames))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
            throw NSError(domain: "QwenTTSService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Buffer allocation failed"])
        }
        try inputFile.read(into: buffer, frameCount: framesToRead)

        let safeFrames = getSafeTrimFrame(buffer: buffer, maxFrames: framesToRead)
        buffer.frameLength = safeFrames

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen_ref_\(UUID().uuidString).wav")

        let outputFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try outputFile.write(from: buffer)

        return tempURL
    }

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
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case voiceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .voiceNotFound:
            return "Voice prompt failed."
        }
    }
}
