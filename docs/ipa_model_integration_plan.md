# Multilingual Phonetic Migration Plan (XLS-R 53 eSpeak)

## 1. Objective
Migrate the inference engine from the orthographic `xlsr-53-english` checkpoint to the phonetic `facebook/wav2vec2-xlsr-53-espeak-cv-ft` model. This enables true IPA extraction and eliminates the orthographic autocorrect behavior.

## 2. CoreML Export Pipeline

The export pipeline remains structurally identical to the previous implementation. We update the model identifier to pull the true phonetic weights.

**`scripts/export_coreml.py`**
```python
import torch
import numpy as np
import coremltools as ct
from transformers import Wav2Vec2ForCTC

def export_phonetic_model():
    model_id = "facebook/wav2vec2-xlsr-53-espeak-cv-ft"
    output_path = "Wav2Vec2Phonetic.mlpackage"
    
    model = Wav2Vec2ForCTC.from_pretrained(model_id).eval()

    class Wrapper(torch.nn.Module):
        def __init__(self, m): 
            super().__init__()
            self.m = m
        def forward(self, x): 
            return self.m(x).logits

    traced = torch.jit.trace(Wrapper(model), torch.randn(1, 16000), strict=False)

    audio_input = ct.TensorType(
        name="audio", 
        shape=(1, ct.RangeDim(16000, 480000)), 
        dtype=np.float32
    )

    mlmodel = ct.convert(
        traced,
        inputs=[audio_input],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16
    )
    
    mlmodel.save(output_path)

if __name__ == "__main__":
    export_phonetic_model()
```

## 3. Swift Architecture Modifications

### A. Inference Engine Vocabulary Update
The new model outputs universal IPA tokens. Extract the exact `vocab.json` from the Hugging Face repository to map the indices correctly.

**`AudioInferenceEngine.swift`**
```swift
import CoreML

class AudioInferenceEngine {
    private let model: MLModel
    
    // Universal eSpeak IPA vocabulary mapping (must match HF vocab.json exactly)
    private let vocabulary: [String] = [
        "<pad>", "<s>", "</s>", "<unk>", "a", "ɪ", "u", "ɔ", "ə", "ɛ", 
        "p", "b", "t", "d", "k", "ɡ", "m", "n", "ŋ", "f", "v", "θ", "ð", 
        "s", "z", "ʃ", "ʒ", "h", "l", "ɹ", "w", "j", " "
    ]
    
    init(modelName: String) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")!
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    // ... Inference extraction methods remain unchanged ...
}
```

### B. Alignment Scorer Overhaul (Dynamic Penalty Matrix)
Instead of a binary string match, the Needleman-Wunsch algorithm must now penalize based on phonetic distance. By mapping IPA symbols to physical articulatory features, we can calculate the substitution penalty dynamically.

**`AlignmentScorerEngine.swift`**
```swift
import Foundation

struct PhoneticFeature {
    let isVowel: Bool
    let voicing: Float       // 0.0 (unvoiced) to 1.0 (voiced)
    let place: Float         // 0.0 (bilabial/front) to 1.0 (glottal/back)
    let manner: Float        // 0.0 (stop) to 1.0 (approximant/vowel)
}

struct IPAPenaltyMatrix {
    // A mapping of IPA symbols to their physical acoustic traits
    static let featureMap: [String: PhoneticFeature] = [
        "p": PhoneticFeature(isVowel: false, voicing: 0.0, place: 0.0, manner: 0.0),
        "b": PhoneticFeature(isVowel: false, voicing: 1.0, place: 0.0, manner: 0.0),
        "t": PhoneticFeature(isVowel: false, voicing: 0.0, place: 0.3, manner: 0.0),
        "d": PhoneticFeature(isVowel: false, voicing: 1.0, place: 0.3, manner: 0.0),
        "a": PhoneticFeature(isVowel: true, voicing: 1.0, place: 0.5, manner: 1.0),
        "ɪ": PhoneticFeature(isVowel: true, voicing: 1.0, place: 0.8, manner: 1.0)
        // Note: Expand dictionary with remaining target IPA symbols
    ]
    
    static func substitutionCost(target: String, inferred: String) -> Float {
        if target == inferred { return 0.0 }
        
        guard let f1 = featureMap[target], let f2 = featureMap[inferred] else {
            return 1.0 // Max penalty for unmapped or unknown tokens
        }
        
        // Massive penalty for substituting a vowel for a consonant
        if f1.isVowel != f2.isVowel { return 1.0 }
        
        // Calculate Euclidean distance across articulatory features
        let voiceDiff = pow(f1.voicing - f2.voicing, 2)
        let placeDiff = pow(f1.place - f2.place, 2)
        let mannerDiff = pow(f1.manner - f2.manner, 2)
        
        let totalDistance = sqrt(voiceDiff + placeDiff + mannerDiff)
        
        // Normalize the distance to a 0.0 - 1.0 penalty scale
        // Maximum possible distance in this vector space is ~1.73 (sqrt(3))
        return min(totalDistance / 1.73, 1.0)
    }
}
```

## 4. Parity & Validation Checks

### A. Mathematical Parity (Python)
Execute `test_parity.py` comparing PyTorch raw logits to the `.mlpackage` logits. Validate that Cosine Similarity exceeds `0.990` to confirm FP16 quantization did not warp the phonetic feature space.

### B. Acoustic Validation (Swift Sandbox)
Run a diagnostic test feeding the system a mispronounced audio file (e.g., "wather" instead of "weather"). 
* **Success Condition:** The greedy decode explicitly outputs `/w a ð ɚ/` instead of autocorrecting to the orthographic English spelling.
* **Matrix Condition:** The dynamic `substitutionCost` assigns a high mathematical penalty for substituting `/ɛ/` with `/a/`, correctly dropping the local GOP score for that specific target phoneme.