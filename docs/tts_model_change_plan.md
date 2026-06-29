# Native MLX Swift Architecture Plan (Zero-Shot Cross-Lingual TTS)

## 1. Objective
Migrate the cross-lingual zero-shot TTS pipeline entirely to a local macOS environment for the `PhonemeInferenceSandbox` application[cite: 3]. This eliminates the external Python FastAPI backend previously used to execute the `mlx-audio` server[cite: 3], leveraging a native Swift MLX audio integration to run Qwen3-TTS or CosyVoice inference directly within the Mac's unified memory space.

## 2. Dependency Management
Integrate the MLX Swift ecosystem into your Xcode project via Swift Package Manager (SPM).

* **Repository:** `https://github.com/Blaizzy/mlx-audio-swift.git`
* **Targets:** Add `MLXAudioTTS` and `MLXAudioCore` to your application target.

## 3. Implementation Modules

### `AudioPreprocessor.swift`
Ensures the user's recorded English prompt is mono, normalized, and downsampled to 16kHz before being passed to the MLX model as the speaker embedding reference.

```swift
import AVFoundation

struct AudioPreprocessor {
    static func processPrompt(fileURL: URL, targetSampleRate: Double = 16000.0) throws -> [Float] {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)!
        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw NSError(domain: "AudioPreprocessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }
        
        let frameCount = AVAudioFrameCount(file.length)
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: inputBuffer)
        
        let targetFrameCount = AVAudioFrameCount(Double(frameCount) * targetSampleRate / format.sampleRate)
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount)!
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        if let error = error { throw error }
        
        guard let channelData = outputBuffer.floatChannelData else { return [] }
        let floats = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        
        return normalizeVolume(floats)
    }
    
    private static func normalizeVolume(_ buffer: [Float]) -> [Float] {
        guard let maxVal = buffer.max(by: { abs($0) < abs($1) }) else { return buffer }
        let peak = abs(maxVal)
        guard peak > 0 else { return buffer }
        return buffer.map { $0 / peak }
    }
}
```

### `MLXTTSService.swift`
Handles model initialization and cross-lingual inference natively on the GPU/Neural Engine, completely replacing the external FastAPI server workflow[cite: 3].

```swift
import Foundation
import MLXAudioTTS
import MLXAudioCore

class MLXTTSService {
    private var ttsModel: Qwen3TTSModel? 
    private let targetSampleRate = 22050.0
    
    func loadModel(modelID: String = "mlx-community/Qwen3-TTS-1.7B-Base") async throws {
        self.ttsModel = try await Qwen3TTSModel.fromPretrained(modelID)
    }
    
    func generateCrossLingualAudio(targetMandarinText: String, englishPromptURL: URL, englishPromptText: String) async throws -> URL {
        guard let model = ttsModel else {
            throw NSError(domain: "MLXTTSService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not initialized"])
        }
        
        let promptAudioData = try AudioPreprocessor.processPrompt(fileURL: englishPromptURL)
        
        let parameters = GenerateParameters(
            maxTokens: 2000,
            temperature: 0.7,
            topP: 0.95
        )
        
        let generatedAudio = try await model.generate(
            text: targetMandarinText,
            referenceAudio: promptAudioData,
            referenceText: englishPromptText,
            parameters: parameters
        )
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("native_mandarin_baseline.wav")
        try saveAudioArray(generatedAudio, sampleRate: targetSampleRate, to: outputURL)
        
        return outputURL
    }
    
    private func saveAudioArray(_ buffer: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count))!
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        
        if let channelData = pcmBuffer.floatChannelData {
            buffer.withUnsafeBufferPointer { ptr in
                channelData[0].initialize(from: ptr.baseAddress!, count: buffer.count)
            }
        }
        
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: pcmBuffer)
    }
}
```

### `AudioBaselineManager.swift`
Orchestrator that ties the native MLX TTS generation directly into your existing `AudioInferenceEngine`[cite: 1, 3] to extract the perfect phonetic target array for the alignment scoring lifecycle[cite: 1, 3].

```swift
import Foundation

class AudioBaselineManager {
    let ttsService = MLXTTSService()
    let inferenceEngine: AudioInferenceEngine
    
    init(inferenceEngine: AudioInferenceEngine) {
        self.inferenceEngine = inferenceEngine
    }
    
    func getTargetPhonemes(mandarinText: String, englishPromptURL: URL, englishPromptText: String) async throws -> [String] {
        if ttsService.ttsModel == nil {
            try await ttsService.loadModel()
        }
        
        // 1. Generate cloned native Mandarin audio entirely on-device
        let baselineAudioURL = try await ttsService.generateCrossLingualAudio(
            targetMandarinText: mandarinText,
            englishPromptURL: englishPromptURL,
            englishPromptText: englishPromptText
        )
        
        // 2. Load the generated WAV back into a float array
        let baselineBuffer = try AudioPreprocessor.processPrompt(fileURL: baselineAudioURL, targetSampleRate: 16000.0)
        
        // 3. Pass to the existing CoreML Wav2Vec2 Engine for greedy decode
        let mlMultiArray = try inferenceEngine.convertToMLMultiArray(baselineBuffer)
        return try inferenceEngine.extractTargetPhonemes(from: mlMultiArray)
    }
}
```