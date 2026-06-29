import Foundation
import MLX
import MLXLMCommon
import MLXAudioCore
import MLXAudioTTS

// MARK: - Constants

/// Using the Base model for zero-shot voice cloning.
private let kModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"

// MARK: - TTSService

/// A native Swift actor that manages the Qwen3-TTS model.
actor TTSService {
    static let shared = TTSService()
    
    private let kReferenceTranscript = """
    When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. \
    The rainbow is a division of white light into many beautiful colors. These take the shape of a \
    long round arch, with its path high above, and its two ends apparently beyond the horizon. \
    There is, according to legend, a boiling pot of gold at one end. People look, but no one ever \
    finds it. When a man looks for something beyond his reach, his friends say he is looking for \
    the pot of gold at the end of the rainbow. Throughout history, the rainbow has been a symbol of \
    hope and a sign of things to come. The vibrant bands of red, orange, yellow, green, blue, and \
    violet curve gracefully across the sky, reminding us of the calm that follows a storm. Scientists \
    observe these wavelengths to understand the physics of light, while artists simply try to capture \
    their fleeting brilliance on canvas.
    """

    private var model: SpeechGenerationModel?
    private var currentPlayer: AudioStreamPlayer?

    // MARK: - Public API
    
    /// Preloads the model into memory.
    func preloadModel() async throws {
        _ = try await loadModelIfNeeded()
    }

    /// Generate speech audio using text-prompted voice design and streaming.
    func generateAudio(text: String, referenceAudioURL: URL?) async throws -> URL {
        let model = try await loadModelIfNeeded()
        
        await currentPlayer?.stop()
        let player = await AudioStreamPlayer(sampleRate: Double(model.sampleRate))
        currentPlayer = player
        
        var allFloats = [Float]()

        let params = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.7,
            topP: 0.9,
            repetitionPenalty: 1.1,
            repetitionContextSize: 20
        )
        
        var refAudioArray: MLXArray? = nil
        var refText: String? = nil
        if let refURL = referenceAudioURL {
            let (_, audioArray) = try loadAudioArray(from: refURL, sampleRate: model.sampleRate)
            refAudioArray = audioArray
            refText = kReferenceTranscript
        }
        
        for try await event in model.generateStream(
            text: text,
            voice: nil,
            refAudio: refAudioArray,
            refText: refText,
            language: nil,
            generationParameters: params
        ) {
            if case .audio(let chunk) = event {
                // Ensure chunk is contiguous float32 array
                let floatArray = chunk.asArray(Float.self)
                allFloats.append(contentsOf: floatArray)
                await player.scheduleBuffer(floatArray)
            }
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native_baseline.wav")

        try AudioUtils.writeWavFile(samples: allFloats, sampleRate: Double(model.sampleRate), fileURL: outputURL)

        return outputURL
    }
    
    func stopAudio() async {
        await currentPlayer?.stop()
    }

    // MARK: - Private

    private func loadModelIfNeeded() async throws -> SpeechGenerationModel {
        if let model { return model }
        let loaded = try await TTS.loadModel(modelRepo: kModelRepo)
        model = loaded
        return loaded
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
