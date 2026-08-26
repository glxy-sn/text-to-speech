# QwenTTS Integration and Inference Pipeline Guide

This guide details the integration of the Qwen Text-to-Speech (QwenTTS) engine into our Swift frontend, primarily located within the `PhonemeInferenceSandbox`. It covers the specific components used, references the related source files, and walks through the end-to-end inference pipeline from text generation to pronunciation scoring.

## Overview of the Pipeline

The inference pipeline in the application follows these major steps:
1. **TTS Synthesis**: QwenTTS generates baseline reference audio from a text prompt.
2. **Target Phoneme Extraction**: A CoreML Wav2Vec2 model analyzes the generated audio to extract the expected phonemes.
3. **User Recording**: The user attempts to speak the same text prompt, and the audio is recorded.
4. **Pronunciation Alignment and Scoring**: The system compares the user's recorded audio against the target phonemes to evaluate pronunciation quality using Goodness of Pronunciation (GOP) scoring.

---

## 1. QwenTTS Integration (`MLXTTSService.swift`)

The QwenTTS model is fully integrated natively on-device leveraging Apple's MLX framework.

### Components and Dependencies
- **Packages**: `MLX`, `MLXLMCommon`, `MLXAudioCore`, `MLXAudioTTS`
- **Model Reference**: Uses the HuggingFace MLX community repo: `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16`. The base model enables zero-shot voice cloning capabilities.
- **Service Protocol**: The `QwenTTSService` actor implements `TTSServiceProtocol`, standardizing operations such as `initialize()`, `synthesize()`, and streaming generation.

### Generation Workflow
The entry point for audio generation is `QwenTTSService.generateAudio()`. 
1. **Initialization**: The service lazy-loads the `SpeechGenerationModel` via `TTS.loadModel(modelRepo:)`.
2. **Streaming Inference**: Uses `model.generateStream()` yielding live audio chunks.
3. **Voice Cloning**: Accepts a `referenceAudioURL`. The reference audio is converted into an `MLXArray` and provided alongside a standard reference transcript.
4. **Live Playback**: Chunks are fed continuously to an `AudioStreamPlayer` for real-time playback.
5. **Disk Write**: The complete audio is accumulated and exported to the temporary directory as `native_baseline.wav` via `AudioUtils.writeWavFile()`.

Performance metrics, including **Time-To-First-Audio (TTFA)** and **Real-Time Factor (RTF)**, are calculated directly within this service.

---

## 2. Orchestration (`PhonemeInferenceViewModel.swift`)

The `PhonemeInferenceViewModel` sits at the center of the application, managing states, coordinating services, and bridging the UI with the backend inference engines.

### Key Responsibilities
- **Model Loading**: Asynchronously preloads the Qwen TTS model on boot.
- **Baseline Generation**: Handles the `generateBaseline()` action, which delegates to `QwenTTSService` (or CosyVoice as an alternative). 
- **Piping Audio to Extractor**: Upon successful generation of `native_baseline.wav`, it loads the audio back into an `MLMultiArray` via `AudioService` and passes it to the `AudioInferenceEngine`.

---

## 3. Target Phoneme Extraction (`AudioInferenceEngine.swift`)

Once the QwenTTS baseline audio is generated, the system establishes a "ground truth" sequence of phonemes for the pronunciation scoring.

### Components
- **Model Reference**: `Wav2Vec2Phonetic.mlmodelc` (CoreML)
- **Engine**: `AudioInferenceEngine`

### Extraction Workflow
1. The synthesized audio (`MLMultiArray`) is wrapped into a `Wav2Vec2Input` feature provider.
2. A forward pass is executed on the `wav2vec2Model` yielding output logits representing probabilities over a predefined phonetic vocabulary.
3. **Greedy Decoding**: The engine runs `runGreedyDecodeWithFrames(logits:)` to extract the most probable sequence of target phoneme symbols (`extractedPhonemes`).

---

## 4. User Recording and Scoring 

To evaluate the user's speech against the QwenTTS baseline, the application captures microphone input and aligns it with the extracted target phonemes.

### Components
- **Recording**: `AudioRecordingService.swift`
- **Alignment & Scoring Engine**: `AlignmentScorerEngine.swift`

### Scoring Workflow
1. **Recording**: `AudioRecordingService` captures the user's attempt and saves it to a local URL.
2. **Logit Extraction**: The user's audio is passed through the same `AudioInferenceEngine` (Wav2Vec2) to obtain the raw probability logits representing what the user actually said.
3. **Pronunciation Scoring**: The `AlignmentScorerEngine` takes over via `scorePronunciation()`.
   - **CTC Forward-Backward Algorithm**: It aligns the user's unsegmented audio logits against the discrete sequence of `targetPhonemes` derived from the QwenTTS baseline.
   - **GOP Calculation**: It calculates the expected probability of each target phoneme given the alignment, outputting a collection of `PhoneScore` objects. These scores contain the symbol, frame length, and the final `gopScore` indicating pronunciation accuracy.

---

## Conclusion
By combining MLX-backed local generation (QwenTTS) with CoreML-backed phonetic evaluation (Wav2Vec2), the application achieves an entirely on-device, low-latency pronunciation evaluation pipeline. `PhonemeInferenceViewModel` bridges these domains, executing the sequence smoothly from reference synthesis to user assessment.
