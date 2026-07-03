import Foundation
import MLX

// MARK: - Shared TTS Types

/// Controls how much of the reference audio is used for voice cloning.
/// Trimming is always performed on the client before synthesis begins,
/// keeping the server (or on-device model) agnostic to voice asset management.
public enum TTSRefLength: String, CaseIterable, Identifiable, Sendable {
    case short  = "short"
    case medium = "medium"
    case long   = "long"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .short:  return "Short (5s)"
        case .medium: return "Medium (10s)"
        case .long:   return "Long (15s)"
        }
    }

    /// Maximum seconds of reference audio to retain before passing to the model.
    public var maxSeconds: Double {
        switch self {
        case .short:  return 5
        case .medium: return 10
        case .long:   return 15
        }
    }
}

// MARK: - Protocol

/// The core protocol that any Text-To-Speech service must conform to.
public protocol TTSServiceProtocol: Actor {

    /// True if the service has been initialized and models are loaded.
    var isReady: Bool { get }

    /// Initialize the TTS service, loading models and preparing for inference.
    func initialize() async throws

    /// Synthesize speech from the given text asynchronously.
    ///
    /// - Parameters:
    ///   - text: The input text to synthesize.
    ///   - onAudioChunk: A callback that provides chunks of synthesized audio (PCM data) as they become available.
    /// - Returns: A complete array of floating point audio samples when generation is complete.
    func synthesize(
        text: String,
        onAudioChunk: (@Sendable ([Float]) -> Void)?
    ) async throws -> [Float]
}
