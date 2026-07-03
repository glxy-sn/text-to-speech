import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// A shared actor to keep the MLX Whisper model loaded in memory, allowing
/// both CosyVoice and Qwen TTS to transcribe reference audio slices instantly.
public actor SharedSTTService {
    public static let shared = SharedSTTService()
    
    private var model: WhisperModel?
    private let repo = "mlx-community/whisper-large-v3-turbo"
    
    /// Preloads the Whisper model if it hasn't been loaded already.
    public func initialize() async throws {
        if model == nil {
            print("Loading Whisper model (\(repo))...")
            model = try await WhisperModel.fromPretrained(repo)
            print("Whisper model loaded.")
        }
    }
    
    /// Transcribes the given audio URL, optionally trimming it to `maxSeconds`.
    public func transcribe(audioURL: URL, maxSeconds: Double? = nil) async throws -> String {
        try await initialize()
        guard let model = model else {
            throw NSError(domain: "SharedSTTService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to load Whisper model"])
        }
        
        let (_, audioArray) = try loadAudioArray(from: audioURL, sampleRate: 16000) // Whisper expects 16kHz
        
        let trimmedAudio: MLXArray
        if let maxSeconds = maxSeconds {
            let maxSamples = Int(maxSeconds * 16000.0)
            if audioArray.ndim == 2 {
                let currentSamples = audioArray.shape[1]
                let end = min(currentSamples, maxSamples)
                trimmedAudio = audioArray[0..<1, 0..<end]
            } else {
                let currentSamples = audioArray.shape[0]
                let end = min(currentSamples, maxSamples)
                trimmedAudio = audioArray[0..<end]
            }
        } else {
            trimmedAudio = audioArray
        }
        
        print("Transcribing with local Whisper...")
        let output = model.generate(audio: trimmedAudio)
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Transcription: \(text)")
        return text
    }
}
