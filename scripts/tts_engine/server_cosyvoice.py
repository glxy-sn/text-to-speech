import os
import sys
import tempfile
import torchaudio
from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional

# Ensure CosyVoice is in the Python path
current_dir = os.path.dirname(os.path.abspath(__file__))
cosyvoice_path = os.path.join(current_dir, 'CosyVoice')
sys.path.append(cosyvoice_path)
sys.path.append(os.path.join(cosyvoice_path, 'third_party/Matcha-TTS'))

from huggingface_hub import snapshot_download
from cosyvoice.cli.cosyvoice import CosyVoice3
from cosyvoice.utils.file_utils import load_wav

app = FastAPI()

print("Downloading/Loading CosyVoice3-0.5B model from HuggingFace...")
model_dir = snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512')
print("Initializing CosyVoice3...")
cosyvoice = CosyVoice3(model_dir)

@app.get("/health")
async def health():
    return {"status": "ok", "model": "Fun-CosyVoice3-0.5B-2512"}

@app.post("/generate/")
async def generate_audio(
    target_text: str = Form(...),
    reference_text: Optional[str] = Form(None),
    reference_audio: UploadFile = File(...),
    speed: float = Form(1.0)
):
    import torch
    import whisper
    
    # Save the uploaded file temporarily
    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_ref:
        temp_ref.write(await reference_audio.read())
        temp_ref_path = temp_ref.name
        
    try:
        # 1. Trim leading and trailing silences to avoid static/silence corruption
        speech, sample_rate = torchaudio.load(temp_ref_path, backend='soundfile')
        duration_before = speech.shape[1] / sample_rate
        
        abs_speech = torch.abs(speech).mean(dim=0)
        active_indices = torch.nonzero(abs_speech > 0.005)
        if active_indices.shape[0] > 0:
            start_idx = active_indices[0].item()
            end_idx = active_indices[-1].item()
            speech = speech[:, start_idx:end_idx+1]
            print(f"Trimmed leading/trailing silence: {duration_before:.2f}s -> {speech.shape[1]/sample_rate:.2f}s")
            torchaudio.save(temp_ref_path, speech, sample_rate)
            
        duration = speech.shape[1] / sample_rate
        
        # 2. Transcribe/Slice with Whisper
        w_model = None
        if not reference_text or duration > 10.0:
            print("Loading Whisper to auto-transcribe reference audio...")
            w_model = whisper.load_model("base")
            result = w_model.transcribe(temp_ref_path, language="en")
            auto_transcript = result["text"].strip()
            if not reference_text:
                reference_text = auto_transcript
        
        actual_duration = duration
        
        # 3. Perform semantic slicing to optimal 3s-8s if reference is > 10s
        if duration > 10.0 and w_model is not None:
            print(f"Audio is {duration:.2f}s. Performing semantic slicing to optimal range...")
            valid_text = ""
            slice_end_time = 0.0
            
            for seg in result["segments"]:
                if seg["end"] <= 8.0:
                    valid_text += seg["text"] + " "
                    slice_end_time = seg["end"]
                else:
                    break
                    
            if slice_end_time == 0.0:
                slice_end_time = min(8.0, duration)
                valid_text = reference_text
                print("WARNING: First Whisper segment exceeds 8s. Falling back to hard 8s slice.")
                
            reference_text = valid_text.strip()
            actual_duration = slice_end_time
            print(f"Semantically sliced to {slice_end_time:.2f}s, text: '{reference_text}'")
            
            # Slice audio and save
            max_frames = int(slice_end_time * sample_rate)
            speech = speech[:, :max_frames]
            
            sliced_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
            torchaudio.save(sliced_temp.name, speech, sample_rate)
            
            # Clean up old temp file
            if os.path.exists(temp_ref_path):
                os.remove(temp_ref_path)
            temp_ref_path = sliced_temp.name

        print(f"Final reference transcript: '{reference_text}'")
        
        # Calculate speaking rate of reference audio to normalize speed on top of client request
        char_count = len(reference_text)
        current_cps = char_count / actual_duration if actual_duration > 0 else 14.0
        TARGET_CPS = 14.0
        normalized_factor = TARGET_CPS / current_cps
        final_speed = speed * normalized_factor
        print(f"Reference CPS: {current_cps:.2f} | Normalizing Factor: {normalized_factor:.2f} | Final Speed: {final_speed:.2f}")

        # Run Zero-Shot inference
        output = cosyvoice.inference_zero_shot(
            target_text, 
            reference_text, 
            temp_ref_path, 
            stream=False, 
            speed=final_speed
        )
        
        audio_chunks = []
        for j in output:
            audio_chunks.append(j['tts_speech'])
            
        if not audio_chunks:
            return {"error": "Failed to generate audio"}
            
        # Stitch all chunks together
        final_audio = torch.cat(audio_chunks, dim=1)
            
        # Save output to temporary file
        out_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
        torchaudio.save(out_temp.name, final_audio, cosyvoice.sample_rate)
        
        return FileResponse(out_temp.name, media_type="audio/wav", filename="generated.wav")
    finally:
        # Clean up temporary uploaded/sliced files
        if os.path.exists(temp_ref_path):
            os.remove(temp_ref_path)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
