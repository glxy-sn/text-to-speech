import os
import sys
import librosa
import numpy as np
import soundfile as sf
from mlx_audio.tts.generate import generate_audio, remove_silence_on_both_ends
import mlx_whisper

def test_generate(run_num):
    ref_audio_path = "/Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox/PhonemeInferenceSandbox/VoiceResources/savio.wav"
    
    # 1. Apply VAD
    y, sr = librosa.load(ref_audio_path, sr=None)
    y = remove_silence_on_both_ends(y, sr, window_duration=0.1, volume_threshold=0.015)
    
    # Transcribe to get perfect text
    temp_vad = "temp_vad.wav"
    sf.write(temp_vad, y, sr)
    result = mlx_whisper.transcribe(temp_vad, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", word_timestamps=True)
    
    segments = result.get("segments", [])
    crop_end_time = None
    cropped_text = []
    
    for segment in segments:
        for word in segment.get("words", []):
            word_text = word["word"]
            cropped_text.append(word_text)
            if any(p in word_text for p in [".", ",", "!", "?"]) and word["end"] >= 3.0:
                crop_end_time = word["end"]
                break
        if crop_end_time:
            break
            
    if not crop_end_time:
        crop_end_time = 5.0
        
    ref_text = "".join(cropped_text).strip()
    
    print(f"[{run_num}] Cropping exactly at {crop_end_time}s on punctuation boundary.")
    print(f"[{run_num}] Ref Text: {ref_text}")
    
    crop_samples = int((crop_end_time + 0.1) * sr)
    y_cropped = y[:crop_samples]
    
    temp_ref = f"temp_ref_greedy_{run_num}.wav"
    sf.write(temp_ref, y_cropped, sr)
    
    # 3. Target Text
    target_text = "This is a test of the CosyVoice generation pipeline. I am trying to figure out why it occasionally outputs gibberish or repeats itself."
    
    # 4. Generate kwargs
    kwargs = {
        "text": target_text,
        "model": "mlx-community/Fun-CosyVoice3-0.5B-2512-8bit",
        "ref_audio": temp_ref,
        "ref_text": ref_text, # TRUE ZERO-SHOT MODE
        "stt_model": None, # Disable auto-transcription
        "file_prefix": f"test_output_greedy_{run_num}",
        "lang_code": "auto",
        "temperature": 1.0, # SAMPLING

        "repetition_penalty": 1.0,
        "repetition_context_size": 0,
    }
    
    print(f"[{run_num}] Running generate_audio (TRUE GREEDY ZERO-SHOT)...")
    generate_audio(**kwargs)
    print(f"[{run_num}] Done!")
    
    # Transcribe output
    out_file = f"test_output_greedy_{run_num}_000.wav"
    result_out = mlx_whisper.transcribe(out_file, path_or_hf_repo="mlx-community/whisper-large-v3-turbo")
    out_text = result_out["text"].strip()
    print(f"[{run_num}] OUTPUT TRANSCRIPT: {out_text}")
    print("-" * 50)

if __name__ == "__main__":
    for i in range(1, 4):
        test_generate(i)
