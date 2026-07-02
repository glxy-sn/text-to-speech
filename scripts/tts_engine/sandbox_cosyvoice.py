import os
import sys
import torchaudio

# Ensure CosyVoice is in the Python path
current_dir = os.path.dirname(os.path.abspath(__file__))
cosyvoice_path = os.path.join(current_dir, 'CosyVoice')
sys.path.append(cosyvoice_path)
# Also add third_party/Matcha-TTS
sys.path.append(os.path.join(cosyvoice_path, 'third_party/Matcha-TTS'))

# We can force CPU if MPS is unstable by setting CUDA_VISIBLE_DEVICES="" and checking torchaudio backend
from huggingface_hub import snapshot_download
from cosyvoice.cli.cosyvoice import CosyVoice3
from cosyvoice.utils.file_utils import load_wav

def test_zero_shot(reference_audio_path, reference_text, target_text, output_path):
    print("Downloading/Loading CosyVoice3-0.5B model from HuggingFace...")
    # Use HuggingFace instead of modelscope
    model_dir = snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512')
    print(f"Model loaded from: {model_dir}")
    
    print("Initializing CosyVoice3...")
    cosyvoice = CosyVoice3(model_dir)
    
    print(f"Generating zero-shot TTS...\nTarget Text: {target_text}")
    # inference_zero_shot expects the raw file path, not a loaded tensor
    output = cosyvoice.inference_zero_shot(target_text, reference_text, reference_audio_path, stream=False)
    
    for i, j in enumerate(output):
        out_file = f"{output_path.replace('.wav', '')}_{i}.wav"
        torchaudio.save(out_file, j['tts_speech'], cosyvoice.sample_rate)
        print(f"Saved generated audio to: {out_file}")

if __name__ == '__main__':
    # We need a dummy reference audio. Let's check if the user has one, 
    # or use a generic one if we can find it.
    test_audio = os.path.join(cosyvoice_path, "asset", "cross_lingual_prompt.wav")
    if not os.path.exists(test_audio):
        print(f"Please provide a test audio file at '{test_audio}' or modify the script path.")
        sys.exit(1)
        
    reference_text = "对于如同星辰一般璀璨的你，我不想用普通的语言去形容"
    target_text = "Hello, I am testing the CosyVoice zero-shot text to speech capabilities. The intonation should be natural and not completely flat like the original reference."
    output_dir = os.path.join(current_dir, "test_outputs")
    os.makedirs(output_dir, exist_ok=True)
    test_zero_shot(test_audio, reference_text, target_text, os.path.join(output_dir, "cosyvoice_output.wav"))
