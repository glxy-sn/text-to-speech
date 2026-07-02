import os
import sys
import tempfile
import torchaudio
from flask import Flask, render_template, request, jsonify, send_file
import glob

# Ensure CosyVoice is in the Python path
current_dir = os.path.dirname(os.path.abspath(__file__))
cosyvoice_path = os.path.join(current_dir, 'CosyVoice')
sys.path.append(cosyvoice_path)
sys.path.append(os.path.join(cosyvoice_path, 'third_party/Matcha-TTS'))

from huggingface_hub import snapshot_download
from cosyvoice.cli.cosyvoice import CosyVoice
from cosyvoice.utils.file_utils import load_wav

app = Flask(__name__)

# Load model globally
print("Downloading/Loading CosyVoice3-0.5B model from HuggingFace...")
from cosyvoice.cli.cosyvoice import CosyVoice3
import ssl
ssl._create_default_https_context = ssl._create_unverified_context
model_dir = snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512')
print("Initializing CosyVoice3...")
cosyvoice = CosyVoice3(model_dir)

# Path to VoiceResources
VOICE_RESOURCES_DIR = os.path.join(current_dir, "../../PhonemeInferenceSandbox/PhonemeInferenceSandbox/VoiceResources")

@app.route('/')
def index():
    # Load available voices from VoiceResources
    available_voices = []
    if os.path.exists(VOICE_RESOURCES_DIR):
        for f in os.listdir(VOICE_RESOURCES_DIR):
            if f.endswith('.wav'):
                available_voices.append(f)
    return render_template('index.html', voices=available_voices)

@app.route('/generate', methods=['POST'])
def generate_audio():
    target_text = request.form.get('target_text', '')
    speed = float(request.form.get('speed', 1.0))
    voice_file = request.form.get('voice_file', '')
    mode = request.form.get('mode', 'zero_shot')
    language = request.form.get('language', 'auto')
    seed = int(request.form.get('seed', 0))
    
    from cosyvoice.utils.common import set_all_random_seed
    set_all_random_seed(seed)
    
    if language != 'auto':
        target_text = f"<|{language}|>{target_text}"
    
    reference_audio = request.files.get('reference_audio')
    temp_ref_path = None
    
    if reference_audio and reference_audio.filename:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_ref:
            reference_audio.save(temp_ref)
            temp_ref_path = temp_ref.name
    elif voice_file:
        temp_ref_path = os.path.join(VOICE_RESOURCES_DIR, voice_file)
        if not os.path.exists(temp_ref_path):
            return jsonify({"error": "Voice file not found"}), 400
    else:
        return jsonify({"error": "No reference audio provided"}), 400

    try:
        # Load audio first and trim leading/trailing silence to avoid voice clone corruption
        import torch
        speech, sample_rate = torchaudio.load(temp_ref_path)
        duration_before = speech.shape[1] / sample_rate
        
        abs_speech = torch.abs(speech).mean(dim=0)
        active_indices = torch.nonzero(abs_speech > 0.005)
        if active_indices.shape[0] > 0:
            start_idx = active_indices[0].item()
            end_idx = active_indices[-1].item()
            speech = speech[:, start_idx:end_idx+1]
            print(f"Trimmed leading/trailing silence from reference audio: {duration_before:.2f}s -> {speech.shape[1]/sample_rate:.2f}s")
            
            # Save trimmed version back to temp path
            torchaudio.save(temp_ref_path, speech, sample_rate)
            
        duration = speech.shape[1] / sample_rate

        # Transcribe FULL audio first to get semantic timestamps
        print("Loading Whisper to auto-transcribe FULL reference audio...")
        import whisper
        # Use small model to be fast but accurate
        w_model = whisper.load_model("base")
        result = w_model.transcribe(temp_ref_path, language="en")
        
        actual_duration = duration
        reference_text = result["text"].strip()

        # If reference audio is > 10s, we slice it to prevent performance degradation
        # We perform semantic slicing using Whisper segment timestamps to avoid mid-word cutoffs
        if duration > 10.0:
            print(f"Audio is {duration}s. Performing semantic slicing to optimal 3s-10s range...")
            valid_text = ""
            slice_end_time = 0.0
            
            for seg in result["segments"]:
                # Accumulate segments until we reach the ~8s limit
                if seg["end"] <= 8.0:
                    valid_text += seg["text"] + " "
                    slice_end_time = seg["end"]
                else:
                    break
                    
            if slice_end_time == 0.0:
                # Fallback if the first segment somehow exceeds 8s
                slice_end_time = min(8.0, duration)
                valid_text = result["text"].strip()
                print("WARNING: First Whisper segment exceeds 8s. Falling back to hard 8s slice.")
                
            reference_text = valid_text.strip()
            actual_duration = slice_end_time
            print(f"Semantically sliced to {slice_end_time:.2f}s")
            
            # Slice audio perfectly at the sentence/segment boundary
            max_frames = int(slice_end_time * sample_rate)
            speech = speech[:, :max_frames]
            
            # Save sliced audio to a temporary file
            sliced_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
            torchaudio.save(sliced_temp.name, speech, sample_rate)
            
            if temp_ref_path != os.path.join(VOICE_RESOURCES_DIR, voice_file):
                os.remove(temp_ref_path) # Clean up original temp if it was an upload
            temp_ref_path = sliced_temp.name
            
        print(f"Final aligned reference text: {reference_text}")

        # Calculate speaking rate of the reference audio to normalize output speed
        # actual_duration is the length of the audio chunk that was just transcribed
        actual_duration = actual_duration
        char_count = len(reference_text)
        current_cps = char_count / actual_duration if actual_duration > 0 else 14.0
        
        # Standard baseline characters per second
        TARGET_CPS = 14.0
        
        # If speaker is slow (e.g., 10 cps), factor = 1.4 (speed it up to baseline).
        normalized_factor = TARGET_CPS / current_cps
        
        # Apply the user's slider choice on top of the normalized baseline
        final_speed = speed * normalized_factor
        print(f"Reference CPS: {current_cps:.2f} | Normalizing Factor: {normalized_factor:.2f} | Final Speed: {final_speed:.2f}")

        import torch
        if mode == 'cross_lingual':
            print(f"Generating audio in CROSS-LINGUAL mode with final_speed={final_speed:.2f}...")
            output = cosyvoice.inference_cross_lingual(
                target_text, 
                temp_ref_path, 
                stream=False, 
                speed=final_speed
            )
        else:
            print(f"Generating audio in ZERO-SHOT mode with final_speed={final_speed:.2f}...")
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
            return jsonify({"error": "Failed to generate audio"}), 500
            
        # Stitch all chunks together along the time dimension (dim=1)
        final_audio = torch.cat(audio_chunks, dim=1)
            
        # Save output to temporary file
        out_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
        torchaudio.save(out_temp.name, final_audio, cosyvoice.sample_rate)
        
        return send_file(out_temp.name, mimetype="audio/wav", as_attachment=False)
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
    finally:
        # Clean up temporary uploaded or sliced files
        if temp_ref_path and temp_ref_path != os.path.join(VOICE_RESOURCES_DIR, voice_file) and os.path.exists(temp_ref_path):
            os.remove(temp_ref_path)

if __name__ == '__main__':
    # Add a cache busting for static files during dev
    app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0
    app.run(host='0.0.0.0', port=5050, debug=True, use_reloader=False)
