import Foundation
import MLX

/// The core protocol that any Text-To-Speech service must conform to.
public protocol TTSServiceProtocol: Sendable {
    
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
