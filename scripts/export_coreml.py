import torch
import numpy as np
import coremltools as ct
from transformers import Wav2Vec2ForCTC

def export_wav2vec2_to_coreml(model_id="facebook/wav2vec2-xlsr-53-espeak-cv-ft", output_path="Wav2Vec2Phonetic.mlpackage"):
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
