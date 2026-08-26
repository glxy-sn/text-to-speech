# Project Journal: CosyVoice 3 MLX Port & Python Bridge Pivot

## Current State of the Project (July 2, 2026)
- **Goal:** Originally aimed to port the **CosyVoice 3** TTS model to run locally on macOS in-process using the `MLX` framework. We wanted it to run natively within our Swift frontend without relying on an external Python process.
- **Progress Made:** 
  - Successfully compiled all CosyVoice submodules in Swift (`CosyVoiceFrontend`, `CosyVoiceTTSService`, `CosyVoiceSpeechTokenizer`, `CosyVoice3LM`, `CosyVoiceFlowMatcher`, `CosyVoiceHiFT`, and `CosyVoiceCampPlus`).
  - Resolved `ModelInfo` initialization syntax errors and backing storage issues using `fix_modules.py`.
- **Blockers & Parity Issues:** 
  - During runtime integration, we encountered recurrent shape matching and dimensionality issues between Swift MLX tensor allocations and the reference Python models (especially around Matcha-TTS/FlowMatcher inputs and the Speech Tokenizer audio feature alignment).
  - Debugging these discrepancies (e.g., exact padding behaviors, STFT differences, and complex weight mapping schemes) introduced massive engineering overhead with slow iterative cycles.
  - **Decision:** Pivot away from a native in-process MLX port for CosyVoice to a local **Python Bridge** utilizing **FastAPI**. This approach guarantees model correctness, simplifies the codebase, and accelerates deployment while keeping Qwen3-TTS as the native MLX alternative.

---

## Pivot Plan: FastAPI Python Bridge
Instead of executing the complex model layers locally in Swift, we will run the official Python CosyVoice engine locally via an HTTP service.

### 1. Verification of the Python Sandbox Web UI
Before connecting the Swift frontend, we will test the model using the prebuilt sandbox UI in [scripts/tts_engine](file:///Users/vio/PycharmProjects/text-to-speech/scripts/tts_engine).

* **How to run the Sandbox (Flask):**
  1. Open a terminal and navigate to the project directory:
     ```bash
     cd /Users/vio/PycharmProjects/text-to-speech/scripts/tts_engine
     ```
  2. Activate the dedicated virtual environment:
     ```bash
     source ../../.venv_cosyvoice/bin/activate
     ```
  3. Start the Flask application:
     ```bash
     python app.py
     ```
  4. Open `http://localhost:5050` in a web browser.
  5. Test zero-shot voice cloning by uploading or recording reference audio and entering target text.

* **How to run the FastAPI Bridge:**
  1. Under the same active virtual environment, start the FastAPI server:
     ```bash
     python server_cosyvoice.py
     ```
  2. The service runs on `http://localhost:8000` and exposes a `/generate/` POST endpoint.

---

## Swift Frontend Refactoring Guide ([PhonemeInferenceSandbox](file:///Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox))

To connect our Swift frontend to the Python bridge, we must update the code in the [PhonemeInferenceSandbox](file:///Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox/PhonemeInferenceSandbox) folder:

### 1. Refactor [CosyVoiceTTSService.swift](file:///Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox/PhonemeInferenceSandbox/CosyVoiceTTSService.swift)
- **Deprecate Native MLX Loading:** Remove local weight loading logic (`loadArrays`), MLX model instances (`CosyVoiceFrontend`, `CosyVoiceSpeechTokenizer`, etc.), and the complex math transformations (STFT, Mel spectrograms).
- **Implement REST API Client:**
  - Create a helper network method to make HTTP `POST` requests to `http://localhost:8000/generate/`.
  - Format the payload as `multipart/form-data`.
  - Parameters required:
    - `target_text`: The text to generate.
    - `reference_text`: The transcription of the reference audio (can use a constant or a dynamic text prompt).
    - `reference_audio`: The `.wav` data loaded from the selected voice clone URL.
- **Audio Output & Performance Tracking:**
  - Save the incoming binary stream (`audio/wav`) to a temporary local file.
  - Calculate `TTFA` (Time to First Byte/Audio) and `RTF` (Real-Time Factor) using stopwatch timers around the URLSession request.
  - Return the `(URL, TTFA, RTF)` tuple conforming to `generateAudio(...)`.

### 2. Update [PhonemeInferenceViewModel.swift](file:///Users/vio/PycharmProjects/text-to-speech/PhonemeInferenceSandbox/PhonemeInferenceSandbox/PhonemeInferenceViewModel.swift)
- Modify `loadModel()` and `generateBaseline()`:
  - Skip local initialization checks for CosyVoice since it is served over the network.
  - Add a lightweight connectivity/health check to verify the python server is running on `localhost:8000`. If it's down, display a helpful error message asking the user to start the python bridge.
