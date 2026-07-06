import os
import uuid
import shutil
import multiprocessing
import tempfile
from fastapi import FastAPI, Form, File, UploadFile, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI(title="CosyVoice 3 Sandbox")

# Allow CORS for easy testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve the static files (UI)
app.mount("/static", StaticFiles(directory="static"), name="static")
app.mount("/voices", StaticFiles(directory="../VoiceResources"), name="voices")
TEMP_DIR = "temp_outputs"
os.makedirs(TEMP_DIR, exist_ok=True)

# Pace normalization target (words per minute)
BASELINE_WPM = 130.0


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
async def read_root():
    with open("static/index.html", "r") as f:
        return f.read()


@app.get("/voices_list")
async def get_voices():
    voices_dir = "../VoiceResources"
    if not os.path.exists(voices_dir):
        return {"voices": []}
    voices = [f for f in os.listdir(voices_dir) if f.endswith("_short.wav")]
    return {"voices": voices}


def run_tts_in_process(kwargs, result_queue):
    """Run TTS generation in a completely isolated process to prevent state leakage.

    Reference audio arrives pre-trimmed from the client. This process:
      1. Applies a server-side safety cap (15 s) — protects small models from long context.
      2. Transcribes the reference with Whisper for pace detection only.
      3. Normalises output speed against a WPM baseline.
      4. Generates audio, letting mlx_audio run its own internal STT via stt_model.
         Passing both stt_model AND a hand-rolled ref_text caused mlx_audio to process
         the target text twice, producing repeated output.
    """
    try:
        from mlx_audio.tts.generate import generate_audio
        import mlx_whisper
        import mlx.core as mx
        import soundfile as sf
        import librosa
        import numpy as np

        ref_audio_path = kwargs.pop("ref_audio")
        user_speed = kwargs.pop("user_speed", 1.0)

        # --- Step 1: Server-side safety cap & VAD ---
        # The 0.5B CosyVoice models degrade / produce gibberish when the Whisper
        # transcript of the reference becomes too long or contains silence at the ends.
        try:
            print("Applying VAD to remove silence on both ends...")
            from mlx_audio.tts.generate import remove_silence_on_both_ends
            y, sr = librosa.load(ref_audio_path, sr=None)
            
            # Apply VAD
            y = remove_silence_on_both_ends(y, sr, window_duration=0.1, volume_threshold=0.015)
            
            # Cap length if still too long
            MAX_REF_SECONDS = 15.0
            max_samples = int(MAX_REF_SECONDS * sr)
            if len(y) > max_samples:
                print(f"Reference is still >{MAX_REF_SECONDS}s after VAD — capping...")
                y = y[:max_samples]
                
            sf.write(ref_audio_path, y, sr)
        except Exception as e:
            print(f"Warning: VAD/Capping failed: {e}")

        # --- Step 2: Transcribe reference audio (for pace detection and zero-shot cloning) ---
        ref_text = kwargs.get("ref_text")
        if not ref_text:
            print(f"Transcribing {ref_audio_path} using mlx_whisper...")
            result = mlx_whisper.transcribe(ref_audio_path, path_or_hf_repo="mlx-community/whisper-large-v3-turbo-4bit")
            ref_text = result["text"].strip()
            print(f"Transcript: {ref_text}")
        else:
            print(f"Using client-provided transcript: {ref_text}")
            
        ref_text = ref_text.strip()
        kwargs["ref_text"] = ref_text

        # --- Step 3: Pace detection & normalization ---
        audio_info = sf.info(ref_audio_path)          # re-read after potential cap
        audio_duration_sec = audio_info.duration
        word_count = len(ref_text.split())
        duration_min = max(audio_duration_sec / 60.0, 0.01)
        detected_wpm = word_count / duration_min
        print(f"Detected pace: {detected_wpm:.1f} WPM (baseline: {BASELINE_WPM} WPM)")

        norm_factor = BASELINE_WPM / detected_wpm if detected_wpm > 0 else 1.0
        # Clamp normalization to a safe range
        norm_factor = max(0.6, min(1.6, norm_factor))
        # Combine with user speed slider, clamp final to [0.5, 2.0]
        final_speed = max(0.5, min(2.0, norm_factor * user_speed))
        print(f"Norm factor: {norm_factor:.3f}  |  User speed: {user_speed:.2f}x  |  Final speed: {final_speed:.3f}x")

        # Explicitly clear MLX metal memory before generating
        mx.metal.clear_cache()

        # --- Step 4: Generate audio ---
            
        kwargs["ref_audio"] = ref_audio_path
        kwargs["speed"] = final_speed
        generate_audio(**kwargs)

        result_queue.put({
            "error": None,
            "detected_wpm": round(detected_wpm, 1),
            "norm_factor": round(norm_factor, 3),
            "final_speed": round(final_speed, 3),
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        result_queue.put({"error": str(e)})



@app.post("/generate")
async def generate_tts(
    text: str = Form(...),
    reference_audio: UploadFile = File(...),   # Binary WAV uploaded by client (pre-trimmed)
    ref_text: str = Form(None),                # Client-provided transcription (optional)
    target_language: str = Form("auto"),        # "auto" | "chinese"
    speed: float = Form(1.0),                  # User pace slider (0.5–2.0)
):
    ref_tmp_path = None
    try:
        if not text:
            raise HTTPException(status_code=400, detail="Text is required")
            
        # Punctuation Hack: Ensure target text ends with terminal punctuation
        # This prevents the autoregressive LLM from getting "stuck" and repeating the text twice
        text = text.strip()
        if not text.endswith(('.', '!', '?')):
            text += '.'

        # Save the uploaded reference audio to a temporary file
        suffix = os.path.splitext(reference_audio.filename or "ref.wav")[1] or ".wav"
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
            shutil.copyfileobj(reference_audio.file, tmp)
            ref_tmp_path = tmp.name

        # Generate unique output filename
        output_prefix = os.path.join(TEMP_DIR, f"output_{uuid.uuid4().hex}")

        # Dynamic Model Routing
        # Use CosyVoice 2 for pure Chinese to avoid cross-lingual hallucinations
        # Use CosyVoice 3 for everything else (better prosody and zero-shot voice cloning)
        if target_language == "chinese":
            model_id = "mlx-community/CosyVoice2-0.5B-8bit"
        else:
            model_id = "mlx-community/Fun-CosyVoice3-0.5B-2512-8bit"

        kwargs = {
            "text": text,
            "model": model_id,
            "ref_audio": ref_tmp_path,
            "file_prefix": output_prefix,
            "lang_code": "auto",
            "user_speed": speed,
            "temperature": 0.2,
            "repetition_penalty": 1.2,
        }

        if ref_text:
            kwargs["ref_text"] = ref_text
        else:
            kwargs["stt_model"] = "mlx-community/whisper-turbo"

        result_queue = multiprocessing.Queue()
        p = multiprocessing.Process(target=run_tts_in_process, args=(kwargs, result_queue))
        p.start()
        p.join()

        result_data = result_queue.get() if not result_queue.empty() else {"error": "No result from subprocess"}

        if result_data.get("error"):
            raise Exception(f"Subprocess failed: {result_data['error']}")

        if p.exitcode != 0:
            raise Exception("Subprocess crashed unexpectedly")

        output_file = f"{output_prefix}_000.wav"
        if not os.path.exists(output_file):
            raise HTTPException(status_code=500, detail="Generation failed, no audio produced.")

        # Return audio file with pace metadata in custom headers
        return FileResponse(
            output_file,
            media_type="audio/wav",
            headers={
                "X-Detected-WPM": str(result_data.get("detected_wpm", "")),
                "X-Norm-Factor": str(result_data.get("norm_factor", "")),
                "X-Final-Speed": str(result_data.get("final_speed", "")),
                "Access-Control-Expose-Headers": "X-Detected-WPM, X-Norm-Factor, X-Final-Speed",
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Clean up the temporary reference audio file
        if ref_tmp_path and os.path.exists(ref_tmp_path):
            try:
                os.unlink(ref_tmp_path)
            except OSError:
                pass


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
