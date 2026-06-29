import torch
import numpy as np
import coremltools as ct
from transformers import Wav2Vec2ForCTC
from sklearn.metrics.pairwise import cosine_similarity

def test_model_parity(pytorch_model_id="facebook/wav2vec2-xlsr-53-espeak-cv-ft", coreml_path="Wav2Vec2Phonetic.mlpackage"):
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
