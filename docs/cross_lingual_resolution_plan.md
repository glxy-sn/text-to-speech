# Cross-Lingual Instability Resolution Plan

## Background
The user encountered severe hallucinations when attempting zero-shot cross-lingual synthesis on pure Mandarin text (`妈妈早上好`) using an English reference voice. The model continually appended the English reference transcript to the output.

This issue stems from a fundamental limitation in the underlying language model's ability to abruptly code-switch without a semantic context bridge when operating at lower parameter counts (0.5B).

## The Tradeoffs: CosyVoice3 vs. CosyVoice2
Initially, rolling back to `CosyVoice2` was proposed as a solution because it does not suffer from this zero-shot hallucination issue natively. However, reverting to CosyVoice2 comes with **severe performance regressions**:

1. **Audio Naturalness & Prosody:** CosyVoice3 uses a novel multi-task supervised tokenizer trained on emotion recognition and speaker analysis. CosyVoice2 sounds significantly more robotic and flat by comparison.
2. **Zero-Shot Voice Cloning Quality:** CosyVoice3 was trained on ~1,000,000 hours of audio data, compared to CosyVoice2's ~10,000 hours. CosyVoice3 is vastly superior at capturing the vocal timbre and nuances of "in-the-wild" reference voices.
3. **Human Alignment:** CosyVoice3 utilizes Reinforcement Learning (RL) with a differentiable reward model to align the synthesis with human preferences, resulting in far fewer audio glitches and more coherent speech.

**Conclusion:** Swapping to CosyVoice2 solves the language bug but sacrifices the state-of-the-art voice quality that CosyVoice3 provides.

## Recommended Solution: Automated Semantic Bridge & Crop
To retain the superior voice cloning quality of CosyVoice3 while completely bypassing the hallucination bug, we will implement an **Automated Semantic Bridge & Crop** mechanism in the backend.

### How it Works
1. **Detection:** When the user submits a request, the backend detects if the target text is pure Mandarin and the reference voice is English.
2. **Bridging:** If detected, the backend secretly prepends an English "anchor" phrase to the prompt (e.g., `"My friend told me, [Chinese Text]"`). This forces the LLM to ground itself in the English context first, allowing it to transition smoothly into Chinese without hallucinating the reference audio.
3. **Generation:** The model generates the audio flawlessly.
4. **Cropping:** The backend uses `mlx_whisper` to analyze the generated audio. It isolates the exact timestamp where the English anchor phrase ends (e.g., `1.18 seconds`).
5. **Delivery:** The backend slices the audio array to remove the anchor phrase and returns only the pure, high-quality Chinese synthesis to the user.

### Implementation Steps
1. **Modify `main.py`**
   - Add a fast language detection heuristic (checking for Chinese unicode characters).
   - Update the `/generate` endpoint to intercept pure Mandarin requests.
   - Inject the anchor phrase `"My friend told me, "`.
2. **Integrate Whisper Timestamping**
   - After `generate_audio` finishes, pass the temporary WAV file to `mlx_whisper.transcribe(..., path_or_hf_repo="mlx-community/whisper-turbo")`.
   - Extract the `end` timestamp from the first segment containing the anchor phrase.
3. **Audio Slicing**
   - Use `scipy.io.wavfile` or a similar audio array manipulation tool to trim the first `N` seconds of the audio buffer.
   - Save the cropped audio and return it to the frontend.

By implementing this, the user experiences zero regressions in UI or voice quality, and the model behaves as if it perfectly supports pure Mandarin zero-shot generation.
