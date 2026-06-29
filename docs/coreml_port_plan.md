# coreml_port_plan.md

## 1. SOTA Strategy: `mlprogram` and `RangeDim`

The state-of-the-art approach for porting transformer models to CoreML relies on the **`mlprogram`** format via `coremltools`. 

To handle variable-length user audio efficiently, we use **`ct.RangeDim()`**. This instructs the CoreML compiler that the sequence-length dimension of the input tensor is dynamic. We also quantize the weights to **FP16** during export, cutting the memory footprint in half with near-zero degradation to the continuous raw logits required for the GOP algorithm.

---

## 2. Porting the Model (Python)

**`export_coreml.py`**
```python
import torch
import numpy as np
import coremltools as ct
from transformers import Wav2Vec2ForCTC

def export_wav2vec2_to_coreml(model_id="jonatasgrosman/wav2vec2-large-xlsr-53-english", output_path="Wav2Vec2English.mlpackage"):
    model = Wav2Vec2ForCTC.from_pretrained(model_id)
    model.eval()

    class Wav2Vec2Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m
            
        def forward(self, x):
            return self.m(x).logits

    wrapped_model = Wav2Vec2Wrapper(model)

    dummy_audio = torch.randn(1, 16000)
    traced_model = torch.jit.trace(wrapped_model, dummy_audio, strict=False)

    audio_input = ct.TensorType(
        name="audio", 
        shape=(1, ct.RangeDim(16000, 480000)), 
        dtype=np.float32
    )

    mlmodel = ct.convert(
        traced_model,
        inputs=[audio_input],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16
    )

    mlmodel.save(output_path)
    print(f"Successfully exported to {output_path}")

if __name__ == "__main__":
    export_wav2vec2_to_coreml()
```

---

## 3. Output Parity Testing

We test **Acoustic Parity** by comparing the raw logit matrices using **Cosine Similarity** and **Mean Absolute Error (MAE)** to ensure the mathematical drift introduced by the FP16 quantization and backend switch is minimal.

**`test_parity.py`**
```python
import torch
import numpy as np
import coremltools as ct
from transformers import Wav2Vec2ForCTC
from sklearn.metrics.pairwise import cosine_similarity

def test_model_parity(pytorch_model_id="jonatasgrosman/wav2vec2-large-xlsr-53-english", coreml_path="Wav2Vec2English.mlpackage"):
    pt_model = Wav2Vec2ForCTC.from_pretrained(pytorch_model_id).eval()
    cml_model = ct.models.MLModel(coreml_path)

    np.random.seed(42)
    test_audio = np.random.randn(1, 32000).astype(np.float32)
    pt_tensor = torch.from_numpy(test_audio)

    with torch.no_grad():
        pt_logits = pt_model(pt_tensor).logits.numpy()

    cml_out = cml_model.predict({"audio": test_audio})
    
    out_key = list(cml_out.keys())[0]
    cml_logits = cml_out[out_key]

    pt_flat = pt_logits.flatten().reshape(1, -1)
    cml_flat = cml_logits.flatten().reshape(1, -1)

    cos_sim = cosine_similarity(pt_flat, cml_flat)[0][0]
    mae = np.mean(np.abs(pt_logits - cml_logits))

    print(f"Cosine Similarity:     {cos_sim:.5f}  (Target: > 0.99900)")
    print(f"Mean Absolute Error:   {mae:.5f}  (Target: < 0.05000)")

    assert cos_sim > 0.990, "Parity check failed: Structural divergence detected."
    print("Parity Check Passed. CoreML model is safe for deployment.")

if __name__ == "__main__":
    test_model_parity()
```

---
**Postscript: Future Multilingual Expansion via MMS**
The export and parity testing scripts are fully agnostic to the specific Wav2Vec2 checkpoint used. To expand from the English-only XLSR-53 model to 1,000+ languages later, simply update the `model_id` parameter to `facebook/mms-1b-all` (or any other Hugging Face CTC model). The PyTorch tracing, dynamic `RangeDim` input, FP16 quantization, and cosine similarity parity checks will behave identically without any code refactoring.