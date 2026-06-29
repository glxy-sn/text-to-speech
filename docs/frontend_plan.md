# frontend_plan.md

This document outlines the architecture for a local, on-device macOS pronunciation evaluation system. By using the same Wav2Vec2 CoreML model to decode both the MLX TTS output and the user's speech, the system establishes an acoustic normalization loop where model biases cancel out. 

For the English proof of concept, we are utilizing an English-finetuned Wav2Vec2 model to prevent the "multilingual tax" and ensure the sharpest possible logit distributions for accurate Goodness of Pronunciation (GOP) scoring.

## 1. End-to-End System Pipeline

[Target Text] -> [MLX TTS (CosyVoice / Qwen3-TTS)] -> [TTS Audio Buffer]
[TTS Audio Buffer] -> [Wav2Vec2 CoreML (Greedy Decode)] -> [Target Phoneme Array]
[User Mic Buffer] -> [Wav2Vec2 CoreML (Logits Extraction)] -> [MLMultiArray Posteriors]
[Target Phoneme Array] + [MLMultiArray Posteriors] -> [Swift Accelerate Viterbi] -> [GOP Score]

## 2. Component Stack & SOTA Choices

* **Baseline Audio Generation (Zero-Shot TTS):** Qwen3-TTS or CosyVoice3 ported to the Apple Silicon native **MLX Framework**. Running MLX natively avoids the heavy footprint of PyTorch.
* **Phoneme Extraction & Posteriors:** `jonatasgrosman/wav2vec2-large-xlsr-53-english` compiled to a CoreML `.mlpackage`.
* **Aligner & Scorer Engine:** Native Swift using the `Accelerate` framework (`vDSP`, `vForce`). Offloads the heavy matrix operations of the Viterbi trellis directly to the CPU's vector units.

## 3. Implementation Modules

### `TTSGenerationService.swift`
```swift
import Foundation

class TTSGenerationService {
    func generateBaselineAudio(text: String, voicePrompt: String) async throws -> [Float] {
        let request = TTSRequest(text: text, style: voicePrompt)
        return try await MLXAudioEngine.shared.synthesize(request)
    }
}
```

### `AudioInferenceEngine.swift`
```swift
import CoreML

class AudioInferenceEngine {
    private let wav2vec2Model: MLModel
    private let vocabulary: [String] = ["<pad>", "ϵ", "ɑ", "æ", "ʌ", "ɔ", "aʊ", "aɪ", "b", "d", "ð", "eɪ", "ɛ", "ɝ", "f", "ɡ", "h", "ɪ", "i", "ʤ", "k", "l", "m", "n", "ŋ", "oʊ", "ɔɪ", "p", "ɹ", "s", "ʃ", "t", "ʧ", "θ", "ʊ", "u", "v", "w", "j", "z", "ʒ"]
    
    init(modelName: String) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")!
        self.wav2vec2Model = try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    func extractTargetPhonemes(from ttsBuffer: MLMultiArray) throws -> [String] {
        let inputFeature = Wav2Vec2Input(audio: ttsBuffer)
        let output = try wav2vec2Model.prediction(from: inputFeature)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else { return [] }
        return runGreedyDecode(logits: logits)
    }
    
    func extractUserLogits(from userBuffer: MLMultiArray) throws -> MLMultiArray {
        let inputFeature = Wav2Vec2Input(audio: userBuffer)
        let output = try wav2vec2Model.prediction(from: inputFeature)
        return output.featureValue(for: "logits")!.multiArrayValue!
    }
    
    private func runGreedyDecode(logits: MLMultiArray) -> [String] {
        let totalFrames = logits.shape[1].intValue
        let vocabSize = logits.shape[2].intValue
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(logits.dataPointer))
        
        var sequence: [String] = []
        var lastToken = -1
        
        for frame in 0..<totalFrames {
            let offset = frame * vocabSize
            var maxVal: Float = -Float.greatestFiniteMagnitude
            var maxIdx = 0
            
            for v in 0..<vocabSize {
                let val = ptr[offset + v]
                if val > maxVal {
                    maxVal = val
                    maxIdx = v
                }
            }
            
            if maxIdx != 1 && maxIdx != lastToken {
                sequence.append(vocabulary[maxIdx])
            }
            lastToken = maxIdx
        }
        return sequence
    }
}

class Wav2Vec2Input: MLFeatureProvider {
    var featureNames: Set<String> { ["audio"] }
    let audio: MLMultiArray
    init(audio: MLMultiArray) { self.audio = audio }
    func featureValue(for featureName: String) -> MLFeatureValue? {
        return featureName == "audio" ? MLFeatureValue(multiArray: audio) : nil
    }
}
```

### `MathService.swift`
```swift
import Accelerate

struct MathService {
    static func softmaxVectorized(logits: UnsafeMutablePointer<Float>, frameCount: Int, vocabSize: Int) -> [Float] {
        var probabilities = [Float](repeating: 0.0, count: frameCount * vocabSize)
        
        for f in 0..<frameCount {
            let offset = f * vocabSize
            var frameData = Array(UnsafeBufferPointer(start: logits.advanced(by: offset), count: vocabSize))
            
            var maxVal: Float = 0.0
            vDSP_maxv(frameData, 1, &maxVal, vDSP_Length(vocabSize))
            var negMax = -maxVal
            
            var expIn = [Float](repeating: 0.0, count: vocabSize)
            vDSP_vsadd(frameData, 1, &negMax, &expIn, 1, vDSP_Length(vocabSize))
            
            var count = Int32(vocabSize)
            var expOut = [Float](repeating: 0.0, count: vocabSize)
            vvexpf(&expOut, expIn, &count)
            
            var sum: Float = 0.0
            vDSP_sve(expOut, 1, &sum, vDSP_Length(vocabSize))
            
            var frameProbs = [Float](repeating: 0.0, count: vocabSize)
            vDSP_vsdiv(expOut, 1, &sum, &frameProbs, 1, vDSP_Length(vocabSize))
            
            for v in 0..<vocabSize {
                probabilities[offset + v] = frameProbs[v]
            }
        }
        return probabilities
    }
}
```

### `AlignmentScorerEngine.swift`
```swift
import Foundation

struct PhoneScore {
    let symbol: String
    let gopScore: Float
    let frames: Int
}

class AlignmentScorerEngine {
    private let blankIndex = 1
    
    func scorePronunciation(userLogits: MLMultiArray, targetPhonemes: [String], vocabulary: [String]) -> [PhoneScore] {
        let totalFrames = userLogits.shape[1].intValue
        let vocabSize = userLogits.shape[2].intValue
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(userLogits.dataPointer))
        
        let probs = MathService.softmaxVectorized(logits: ptr, frameCount: totalFrames, vocabSize: vocabSize)
        let alignmentMap = runViterbiAlignment(probs: probs, targets: targetPhonemes, vocab: vocabulary, frames: totalFrames, vocabSize: vocabSize)
        
        return calculateGOP(alignment: alignmentMap, probs: probs, targets: targetPhonemes, vocabSize: vocabSize)
    }
    
    private func runViterbiAlignment(probs: [Float], targets: [String], vocab: [String], frames: Int, vocabSize: Int) -> [Int: Int] {
        var map: [Int: Int] = [:]
        let targetIdxs = targets.map { vocab.firstIndex(of: $0) ?? 0 }
        var currIdx = 0
        
        for f in 0..<frames {
            if currIdx >= targetIdxs.count {
                map[f] = targetIdxs.count - 1
                continue
            }
            
            let offset = f * vocabSize
            let targetProb = probs[offset + targetIdxs[currIdx]]
            let blankProb = probs[offset + blankIndex]
            
            map[f] = currIdx
            
            if currIdx + 1 < targetIdxs.count {
                let nextProb = probs[offset + targetIdxs[currIdx + 1]]
                if nextProb > targetProb && nextProb > blankProb {
                    currIdx += 1
                }
            }
        }
        return map
    }
    
    private func calculateGOP(alignment: [Int: Int], probs: [Float], targets: [String], vocabSize: Int) -> [PhoneScore] {
        var metrics: [PhoneScore] = []
        let grouped = Dictionary(grouping: alignment.keys, by: { alignment[$0]! })
        
        for targetIdx in 0..<targets.count {
            guard let frames = grouped[targetIdx], !frames.isEmpty else {
                metrics.append(PhoneScore(symbol: targets[targetIdx], gopScore: -10.0, frames: 0))
                continue
            }
            
            var logSum: Float = 0.0
            for frame in frames {
                let prob = probs[(frame * vocabSize) + targetIdx]
                logSum += log(max(prob, 1e-8))
            }
            
            metrics.append(PhoneScore(symbol: targets[targetIdx], gopScore: logSum / Float(frames.count), frames: frames.count))
        }
        return metrics
    }
}
```

---
**Postscript: Future Multilingual Expansion via MMS**
Because the architecture relies on the standard `Wav2Vec2ForCTC` Hugging Face pipeline, scaling to multilingual support requires zero structural changes to the Swift or Accelerate logic. You simply compile `facebook/mms-1b-all` to a new `.mlpackage`, update the `vocabulary` array in `AudioInferenceEngine.swift` to match the MMS universal IPA mapping, and initialize the engine with the new model file.

***