# TTS Pipeline Integration Guide

**Scope:** QwenTTS Model Pipeline · Audio Preprocessing · Phoneme Alignment · GOP Scoring  
**Project:** PhonemeInferenceSandbox — End-to-End Speech Correction  
**Last Updated:** July 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [QwenTTS Model Pipeline](#2-qwentts-model-pipeline)
   - 2.1 [Model Selection and Loading](#21-model-selection-and-loading)
   - 2.2 [Reference Audio Preparation and Voice Cloning](#22-reference-audio-preparation-and-voice-cloning)
   - 2.3 [Streaming Inference and Live Playback](#23-streaming-inference-and-live-playback)
   - 2.4 [Generation Parameters](#24-generation-parameters)
   - 2.5 [Performance Instrumentation (TTFA and RTF)](#25-performance-instrumentation-ttfa-and-rtf)
3. [Audio Preprocessing](#3-audio-preprocessing)
   - 3.1 [Fade-In Artifact Suppression](#31-fade-in-artifact-suppression)
   - 3.2 [Silence Trimming and Voice Activity Detection (VAD)](#32-silence-trimming-and-voice-activity-detection-vad)
   - 3.3 [High-Pass Denoising Filter](#33-high-pass-denoising-filter)
   - 3.4 [Tempo Normalization](#34-tempo-normalization)
   - 3.5 [Audio Loading and Feature Normalization for Wav2Vec2](#35-audio-loading-and-feature-normalization-for-wav2vec2)
   - 3.6 [Reference Audio Trimming for Voice Cloning](#36-reference-audio-trimming-for-voice-cloning)
4. [Phoneme Alignment](#4-phoneme-alignment)
   - 4.1 [Wav2Vec2 Inference Engine](#41-wav2vec2-inference-engine)
   - 4.2 [Greedy Decoding: Target Phoneme Extraction](#42-greedy-decoding-target-phoneme-extraction)
   - 4.3 [Word-Level Timing via Apple Speech Framework](#43-word-level-timing-via-apple-speech-framework)
   - 4.4 [ASR Timing Alignment to Target Script](#44-asr-timing-alignment-to-target-script)
   - 4.5 [Hybrid Phoneme-to-Word Alignment](#45-hybrid-phoneme-to-word-alignment)
5. [GOP Pronunciation Scoring](#5-gop-pronunciation-scoring)
   - 5.1 [CTC Forward Pass (Alpha)](#51-ctc-forward-pass-alpha)
   - 5.2 [CTC Backward Pass (Beta)](#52-ctc-backward-pass-beta)
   - 5.3 [GOP Score Calculation from Posterior Gamma](#53-gop-score-calculation-from-posterior-gamma)
   - 5.4 [Geminate Post-Processing](#54-geminate-post-processing)
   - 5.5 [Word Score Aggregation](#55-word-score-aggregation)
6. [Full End-to-End Orchestration](#6-full-end-to-end-orchestration)
7. [Data Flow Diagram](#7-data-flow-diagram)
8. [Key File Reference](#8-key-file-reference)

---

## 1. Architecture Overview

The application implements a fully on-device E2E speech correction pipeline. There are two distinct evaluation phases:

**Phase 1 — Baseline Generation:**
The system synthesizes a native reference recording from the target script using the QwenTTS model running locally via MLX. This generated audio is then preprocessed and passed through a CoreML Wav2Vec2 model to extract a canonical phoneme sequence (the "ground truth") that represents the idealized pronunciation.

**Phase 2 — User Evaluation:**
The user speaks the same script into the microphone. The recording undergoes the same preprocessing, and the Wav2Vec2 model extracts its raw acoustic logits. A CTC-based Goodness of Pronunciation (GOP) scorer then uses the canonical phoneme sequence from Phase 1 as a forced-alignment target, computing a confidence score per phoneme. These phoneme scores are grouped back to the word level for display.

The pivot away from CosyVoice was driven by parity issues: the FlowMatcher and Speech Tokenizer layers introduced irreproducible shape mismatches between Swift MLX tensor allocations and the Python reference model, making it impossible to guarantee acoustic correctness. QwenTTS running natively via `MLXAudioTTS` eliminates that class of problem entirely.

---

## 2. QwenTTS Model Pipeline

**Primary File:** `Services/MLXTTSService.swift`

### 2.1 Model Selection and Loading

The service uses `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16` — the **Base** variant, which is specifically chosen because it enables zero-shot voice cloning. The Instruct variant is locked to its built-in voices and cannot accept a reference audio for cloning.

```swift
private let kModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
```

The model is loaded lazily on first use via `loadModelIfNeeded()`. This function caches the `SpeechGenerationModel` in the actor-isolated `model` property so subsequent calls are free. Loading is performed using:

```swift
let loaded = try await TTS.loadModel(modelRepo: kModelRepo)
```

This call downloads the model weights from Hugging Face on first run and caches them locally. On subsequent launches the cached weights are loaded directly from disk.

`QwenTTSService` is declared as a Swift `actor` to serialize all access to the model and prevent concurrent inference calls from racing.

### 2.2 Reference Audio Preparation and Voice Cloning

Before sending reference audio to the model, it is trimmed on a silence boundary using `trimAudio(from:maxSeconds:)`. This is a critical step — providing audio that extends past a natural pause or into non-speech noise degrades the cloned voice quality significantly.

**Trim Duration** is controlled by `TTSRefLength` (`Services/TTSServiceProtocol.swift`):

| Case     | Max Seconds |
|----------|-------------|
| `.short` | 5s          |
| `.medium`| 7s          |
| `.long`  | 9s          |

**Smart Silence Boundary Detection** (`getSafeTrimFrame`): Instead of simply hard-cutting at `maxSeconds`, the function scans backward from the time limit in 100ms steps using a 300ms RMS window. A 300ms window was chosen deliberately — stop consonant closures (like "t" or "p") can produce near-silence for ~100ms, so a shorter window would incorrectly trigger inside a word. If any window has RMS < 0.015 (~−36 dBFS), that position is returned as the trim point:

```swift
let windowFrames = Int(0.3 * sampleRate)  // 300ms window
if rms < 0.015 { return AVAudioFrameCount(currentEnd) }
```

If no clean silence is found, the quietest window position is used as a fallback. The trim must stay within the range `[50% of maxSeconds, maxSeconds]` to prevent trimming too aggressively.

After trimming, the reference audio is transcribed automatically via the local Whisper model (`SharedSTTService`) to produce `refText`, which is passed alongside `refAudio` to the model. The model uses this text-audio pair for voice style conditioning.

**Whisper for Transcription** (`Services/SharedSTTService.swift`): Uses `mlx-community/whisper-large-v3-turbo` loaded via `MLXAudioSTT`. The model is kept resident as a singleton actor (`SharedSTTService.shared`) so it is not reloaded between calls:

```swift
let (_, audioArray) = try loadAudioArray(from: audioURL, sampleRate: 16000)
let output = model.generate(audio: trimmedAudio)
```

### 2.3 Streaming Inference and Live Playback

Generation happens via `model.generateStream(...)`, which yields `GenerationEvent` values asynchronously. Only `.audio` events are consumed:

```swift
for try await event in model.generateStream(
    text: safeText,
    voice: nil,
    refAudio: refAudioArray,
    refText: refText,
    language: targetLanguage,
    generationParameters: params
) {
    if case .audio(let chunk) = event {
        var floatArray = chunk.asArray(Float.self)
        // apply fade-in, accumulate, schedule to player
    }
}
```

Each chunk is immediately forwarded to `AudioStreamPlayer.scheduleBuffer()`, which queues it onto an `AVAudioPlayerNode` backed by a live `AVAudioEngine`. This produces low-latency streaming playback during generation.

After generation completes, the full accumulated `[Float]` buffer is written to disk at `{tmp}/native_baseline.wav` using `AudioUtils.writeWavFile(samples:sampleRate:fileURL:)`.

### 2.4 Generation Parameters

```swift
let params = GenerateParameters(
    maxTokens: 2048,
    temperature: 0.7,
    topP: 1.0,
    repetitionPenalty: 1.0,
    repetitionContextSize: 20
)
```

- **`maxTokens: 2048`** — caps generation length. At the model's 12Hz token rate this is ~170 seconds of audio, far above any expected sentence length.
- **`temperature: 0.7`** — introduces a moderate amount of sampling randomness. Lower values (e.g., 0.3) produce more monotone but stable outputs; higher values increase expressiveness at the cost of stability.
- **`topP: 1.0`** — nucleus sampling disabled; all tokens are in distribution.
- **`repetitionPenalty: 1.0`** — no repetition penalty applied (the model does not exhibit looping behavior for short utterances).

**Text normalization** before inference: If the input text does not end with `.`, `!`, or `?`, a `.` is appended. Without a terminal punctuation, the Qwen model may generate trailing hallucinated audio or fail to close the utterance cleanly.

```swift
if !safeText.hasSuffix(".") && !safeText.hasSuffix("!") && !safeText.hasSuffix("?") {
    safeText += "."
}
```

### 2.5 Performance Instrumentation (TTFA and RTF)

Two latency metrics are tracked to evaluate model performance:

- **TTFA (Time to First Audio):** Time from calling `generateStream` until the first `.audio` chunk arrives. Measures model initialization and initial decoding latency.
- **RTF (Real-Time Factor):** `(totalGenerationTime) / (audioDuration)`. An RTF < 1.0 means generation is faster than real-time playback.

```swift
let startTime = CFAbsoluteTimeGetCurrent()
// ... stream loop ...
let ttfa = (firstChunkTime ?? endTime) - startTime
let audioDuration = Double(allFloats.count) / Double(model.sampleRate)
let rtf = (endTime - startTime) / max(audioDuration, 0.001)
```

---

## 3. Audio Preprocessing

**Primary File:** `Services/AudioRecordingService.swift`  
**Secondary File:** `Services/AudioService.swift`

Both the generated baseline audio and user recordings pass through a defined preprocessing chain before being fed into Wav2Vec2. The exact preprocessing applied depends on the source:

| Step | Baseline (TTS output) | User Recording |
|------|----------------------|----------------|
| Fade-in artifact suppression | YES (in `MLXTTSService`) | NO |
| Silence trim + denoise | YES (`trimSilenceAndDenoise`) | NO |
| Tempo normalization | YES (`normalizeTempo`) | YES (`normalizeTempo`) |
| 16kHz mono resample | YES (`AudioService.loadAudio`) | YES (captured at 16kHz directly) |
| Wav2Vec2 mean/variance norm | YES (`AudioService.loadAudio`) | YES (`AudioService.loadAudio`) |

### 3.1 Fade-In Artifact Suppression

Applied in `MLXTTSService.generateAudio()`, **before** accumulating samples. A 150ms linear volume ramp is applied to the very first samples of the stream. This removes the characteristic "click" or "pop" artifact that the Qwen model sometimes produces at the start of decoding.

```swift
let fadeSamples = Int(0.15 * Double(model.sampleRate)) // 150ms
if samplesReceived < fadeSamples {
    for i in 0..<floatArray.count {
        let globalIndex = samplesReceived + i
        if globalIndex < fadeSamples {
            let multiplier = Float(globalIndex) / Float(fadeSamples)
            floatArray[i] *= multiplier
        }
    }
}
```

The multiplier goes from `0.0` at sample 0 to `1.0` at sample `fadeSamples`, producing a smooth linear ramp. This happens per-chunk, with `samplesReceived` tracking the cumulative offset into the stream.

### 3.2 Silence Trimming and Voice Activity Detection (VAD)

`AudioRecordingService.trimSilenceAndDenoise(audioURL:)` implements a lightweight sample-domain VAD. The amplitude threshold is **0.015** (~−36 dBFS):

```swift
let threshold: Float = 0.015
```

1. **Leading silence:** Scans forward from index 0 until the first sample exceeding the threshold. The trim start point is set to **100ms before** this index (padding) to avoid cutting into speech onset.
2. **Trailing silence:** Same scan, reversed. Trim end point is **100ms after** the last active sample.
3. If the start index >= end index (audio is entirely quiet), the original URL is returned as a fallback.

The trimmed audio region is copied to a new buffer using `memcpy` for efficiency:

```swift
memcpy(dst, src.advanced(by: startIndex), Int(newFrameCount) * MemoryLayout<Float>.stride)
```

### 3.3 High-Pass Denoising Filter

After silence trimming, `trimSilenceAndDenoise` passes the trimmed buffer through an `AVAudioUnitEQ` with a single high-pass band. The cutoff is **80Hz**:

```swift
filterParams.filterType = .highPass
filterParams.frequency = 80.0
```

This removes sub-bass rumble and the low-frequency hallucinations that Wav2Vec2-based models are sensitive to. The filter is applied in offline manual rendering mode (`AVAudioEngine.enableManualRenderingMode(.offline, ...)`) so the entire operation is deterministic and synchronous — no real-time playback occurs during denoising.

The output is written to `baseline_preprocessed.wav` in the same directory as the input.

### 3.4 Tempo Normalization

`AudioRecordingService.normalizeTempo(audioURL:targetScript:targetWPM:)` adjusts the playback speed of the audio to match a target words-per-minute rate. This is applied to **both** the baseline and user recordings to make them acoustically comparable before Wav2Vec2 scoring.

**Default target WPM:** 130 for baseline, 125 for user recording (defaults from `PhonemeInferenceViewModel`).

**Workflow:**
1. Count words in `targetScript` using `NLTokenizer(unit: .word)`.
2. Measure audio duration from `AVAudioFile.length / sampleRate`.
3. Compute `currentWPM = (wordCount / duration) * 60`.
4. Compute `targetRate = targetWPM / currentWPM`.
5. Clamp rate: `max(0.7, min(1.3, targetRate))`. Rates beyond ±30% introduce audible DSP artifacts from `AVAudioUnitTimePitch`.
6. If the rate delta is < 5%, skip processing (no perceptible difference).

Time-stretching is done via `AVAudioUnitTimePitch.rate` in offline rendering mode, preserving pitch (no chipmunk effect):

```swift
let timePitch = AVAudioUnitTimePitch()
timePitch.rate = Float(targetRate)
```

### 3.5 Audio Loading and Feature Normalization for Wav2Vec2

`AudioService.loadAudio(from:targetSampleRate:)` is the final preprocessing step before inference. It produces the `MLMultiArray` input that Wav2Vec2 expects.

1. **Resampling to 16kHz mono**: If the audio format doesn't match the target (16kHz Float32 mono), an `AVAudioConverter` performs the conversion on the fly. Wav2Vec2 was trained exclusively on 16kHz audio — any other sample rate produces garbage outputs.

2. **Mean-Variance Normalization**: The raw PCM samples are normalized to zero mean and unit variance using Accelerate's vectorized `vDSP_normalize`:

```swift
vDSP_normalize(channelData, 1, ptr, 1, &mean, &stdDev, vDSP_Length(frameLength))
```

This is a **required** preprocessing step for Wav2Vec2. The model's feature extractor CNN expects the raw waveform to be normalized this way, matching the training-time preprocessing. Without it, the model's confidence values degrade significantly and phoneme boundaries become unreliable.

   If stddev is below 1e-7 (silent audio), the output array is zeroed rather than dividing by near-zero:

```swift
if stdDev < 1e-7 || stdDev.isNaN {
    // fill with zeros
}
```

3. **Shape**: Output is `MLMultiArray` with shape `[1, frameLength]` (batch x samples).

### 3.6 Reference Audio Trimming for Voice Cloning

Described in Section 2.2, this is handled separately in `MLXTTSService.trimAudio(from:maxSeconds:)` before the reference is passed to `generateStream`. It is distinct from `trimSilenceAndDenoise` in purpose: it prepares the *input* to the TTS model, while `trimSilenceAndDenoise` prepares the *output*.

---

## 4. Phoneme Alignment

Alignment connects the flat stream of phoneme symbols (from Wav2Vec2's CTC decoding) back to the discrete words in the target script. It proceeds in two stages: temporal anchoring via Apple's Speech framework, then acoustic alignment via a dynamic programming algorithm.

### 4.1 Wav2Vec2 Inference Engine

**File:** `Evaluation/AudioInferenceEngine.swift`  
**Model:** `Wav2Vec2Phonetic.mlmodelc` (CoreML, packaged as `Wav2Vec2Phonetic.mlpackage`)

`AudioInferenceEngine` wraps a compiled CoreML model. It is loaded once at app launch via:

```swift
let config = MLModelConfiguration()
config.computeUnits = .cpuAndGPU
let model = try await MLModel.load(contentsOf: modelURL, configuration: config)
```

The model accepts a single feature `"audio"` — the `MLMultiArray` of shape `[1, N]` produced by `AudioService.loadAudio`. The output is a 3D logits tensor of shape `[1, T, V]` where:
- `T` = number of frames (~1 frame per 20ms of audio, i.e., ~50Hz frame rate)
- `V` = vocabulary size (~350 phoneme tokens, including special tokens)

The vocabulary is embedded directly in the `AudioInferenceEngine` struct as a hardcoded array of ~350 IPA symbols. Index 0 is `<pad>` (CTC blank token). The first four entries (`<pad>`, `<s>`, `</s>`, `<unk>`) are reserved and filtered during alignment.

Two distinct inference modes are exposed:

| Method | Input | Output | Usage |
|--------|-------|--------|-------|
| `extractTargetPhonemes(from:)` | TTS audio array | `[(symbol, frame)]` via greedy decode | Baseline phase: build the target phoneme sequence |
| `extractUserLogits(from:)` | User audio array | Raw `MLMultiArray` logits | User phase: preserve raw probabilities for GOP scoring |

### 4.2 Greedy Decoding: Target Phoneme Extraction

`runGreedyDecodeWithFrames(logits:)` produces the canonical phoneme sequence from the baseline audio. It implements standard CTC greedy decoding:

1. For each time frame, find the argmax token index across the vocabulary.
2. If the token index is non-zero (not blank) **and** differs from the previous token, emit the corresponding phoneme symbol.
3. Record the frame index alongside each emitted symbol.

```swift
if maxIdx != 0 && maxIdx != lastToken {
    sequence.append((symbol: vocabulary[maxIdx], frame: frame))
}
```

The `frame` value is a direct index into the model's temporal output — each frame represents approximately **20ms** of audio. These timestamps are used later by the hybrid alignment algorithm.

The result — `phonemesWithFrames: [(symbol: String, frame: Int)]` — is stored on the ViewModel and forms the "target" against which the user's pronunciation is scored.

### 4.3 Word-Level Timing via Apple Speech Framework

**File:** `Evaluation/SpeechAlignmentService.swift`

After extracting phonemes from the baseline, the system obtains word-level timestamps from the preprocessed baseline audio using `SFSpeechRecognizer` (Apple's on-device ASR):

```swift
let request = SFSpeechURLRecognitionRequest(url: audioURL)
request.requiresOnDeviceRecognition = true
```

On-device recognition is required because the alignment pipeline runs entirely locally with no network dependency. The recognition result provides `SFTranscriptionSegment` objects, each containing a `substring` (word), `timestamp` (start time in seconds), and `duration`.

The system then calls `alignTimingsToTarget(targetScript:asrTimings:)` to reconcile the ASR-recognized words with the original target script. This is necessary because ASR can mishear or compress words, and the target script is authoritative.

### 4.4 ASR Timing Alignment to Target Script

`SpeechAlignmentService.alignTimingsToTarget` reconciles ASR output with the canonical target script using **character-level Needleman-Wunsch DP alignment**.

**Why character-level?** Word-level alignment is fragile when ASR contracts contractions, mishears words, or runs words together. Character-level alignment degrades more gracefully.

**Workflow:**
1. Flatten target words into a character array, tracking each character's parent word index.
2. Flatten ASR word timings into characters, linearly interpolating timestamps within each word:
   ```swift
   let durationPerChar = (timing.endTime - timing.startTime) / TimeInterval(chars.count)
   ```
3. Run Needleman-Wunsch DP (match=+2, mismatch=−1, gap=−1) to align the two character sequences. Chinese characters are transliterated to Pinyin before comparison via `CFStringTransform(kCFStringTransformMandarinLatin)`.
4. Back-trace the alignment to assign each target character an ASR character (and thus its interpolated timestamp).
5. Aggregate per-character timestamps back to word boundaries: the word's `startTime` is the timestamp of its first matched character, `endTime` of its last.
6. **Missing word interpolation**: Words with no character match (e.g., the ASR missed them entirely) get their timing linearly interpolated between the surrounding anchored words.

The output is `[WordTiming]` — one entry per word in the target script, with `startTime` and `endTime` in seconds, aligned to the preprocessed audio.

### 4.5 Hybrid Phoneme-to-Word Alignment

**File:** `Evaluation/PhonemeWordAligner.swift`

`PhonemeWordAligner.alignHybrid(targetScript:asrTimings:phonemes:)` assigns each Wav2Vec2 phoneme to its parent word. It combines two signals:

1. **Phonetic similarity** between the text character and the phoneme symbol.
2. **Temporal proximity** between the phoneme's Wav2Vec2 frame timestamp and the word's ASR time window.

This is a **weighted sequence alignment** problem solved with a modified DP. There is also a legacy `align(targetScript:phonemes:)` method (CV-type only, no timing) used as a fallback when ASR fails.

**Text Tokenization:**

Words are extracted using `NLTokenizer(unit: .word)`. Chinese Han characters are individually split into single-character tokens (since each character has its own pronunciation). Numbers are spelled out using `NumberFormatter(numberStyle: .spellOut)` before phoneme matching. English spelling is normalized via `normalizeEnglishSpelling` which removes silent-e, collapses digraphs (th→t, sh→s, ch→c, ph→f), and simplifies vowel clusters (ou→o, ea→e, etc.).

**Phonetic Similarity Scoring (`phoneticSimilarity`):**

The lookup table covers common English grapheme-phoneme correspondences:

```swift
let exactMatches: [String: [String]] = [
    "p": ["p"], "b": ["b"], "t": ["t", "ɾ"], "d": ["d", "ɾ"],
    "r": ["ɹ", "r", "ɚ"], "y": ["j"], ...
]
```

| Condition | Score |
|-----------|-------|
| Exact match or explicit grapheme→phoneme mapping | +3.0 |
| Same place-of-articulation class (labial, alveolar, velar, palatal) | +1.5 |
| Both vowels | +2.0 |
| Both consonants, no class match | 0.0 |
| Vowel/consonant mismatch | −2.0 |

**DP Scoring Matrix:**

The DP cell `dp[i][j]` represents the best score for aligning the first `i` text characters to the first `j` phonemes. Four transitions are available:

| Transition | Score | Notes |
|------------|-------|-------|
| **Match** (advance both) | `phoneticSimilarity − timePenalty` | Standard alignment |
| **Absorb** (text token absorbs multiple phonemes) | `phoneticSimilarity − timePenalty` (advance j only) | Handles affricates, diphthongs |
| **Delete** (skip text token) | −1.5 | Cheap — silent letters are common |
| **Insert** (skip phoneme) | −100.0 | Very expensive — real acoustic evidence should not be discarded |

**Time Penalty:**

Each match/absorb is penalized proportionally to how far the phoneme's timestamp falls outside the word's ASR time window:

```swift
let timeDistance = max(0, pToken.timestamp - tToken.endTime)
                 + max(0, tToken.startTime - pToken.timestamp)
let timePenalty = timeDistance * timePenaltyFactor  // factor = 20.0
```

This "anchors" phonemes temporally, preventing a phoneme from jumping to a word on the other side of the utterance.

**Coarticulation Handling:**

During back-trace, if a text token is *deleted* (skipped) due to coarticulation (e.g., the "t" in "just to" is merged into a single acoustic event), the algorithm checks whether the adjacent phoneme has a class match. If so, that adjacent phoneme is *shared* between both words — it contributes to the score of the word whose text token was skipped, as well as the word it was originally assigned to:

```swift
let sim = phoneticSimilarity(char: skippedToken.char, phoneme: pToken.symbol)
if sim >= 1.5 { // Class match or perfect match
    assignments[currJ-1]!.append(skippedToken.wordIndex)
}
```

---

## 5. GOP Pronunciation Scoring

**File:** `Evaluation/AlignmentScorerEngine.swift`  
**Math Helper:** `Services/MathService.swift`

The Goodness of Pronunciation (GOP) score measures how likely a human's uttered phoneme is, given the acoustic model and the forced alignment to the target phoneme sequence. It is computed via a full CTC forward-backward algorithm over the user's Wav2Vec2 logits.

The entry point is `AlignmentScorerEngine.scorePronunciation(userLogits:targetPhonemes:vocabulary:greedyAnchors:)`.

**Step 0 — Softmax Conversion:**

The raw logits from Wav2Vec2 are first converted to probabilities using a vectorized softmax implemented with Accelerate (`vDSP`, `vvexpf`) in `MathService.softmaxVectorized`. The subtraction of the per-frame maximum before exponentiation is critical for numerical stability (the log-sum-exp trick):

```swift
vDSP_vsadd(frameData, 1, &negMax, &expIn, 1, vDSP_Length(vocabSize))
vvexpf(&expOut, expIn, &count)
vDSP_vsdiv(expOut, 1, &sum, &frameProbs, 1, vDSP_Length(vocabSize))
```

**CTC Label Sequence Construction:**

The target phoneme list is expanded into a CTC label sequence `E` of length `L = 2M + 1` by interleaving blank tokens (index 0) between each phoneme:

```
E = [blank, phoneme₀, blank, phoneme₁, blank, ..., blank, phonemeₘ₋₁, blank]
```

Long-vowel markers (`ː`) are stripped before vocabulary lookup, since the CoreML model's vocabulary uses the base phoneme form:

```swift
let symbol = targets[k].replacingOccurrences(of: "ː", with: "")
E[2*k+1] = vocab.firstIndex(of: symbol) ?? blankIndex
```

### 5.1 CTC Forward Pass (Alpha)

`alpha[t][s]` is the log probability that the model produced the label prefix `E[0..s]` using frames `0..t`.

**Initialization:**
```
alpha[0][0] = log P(blank | frame 0)
alpha[0][1] = log P(phoneme₀ | frame 0)
```

**Recurrence** (for `t > 0`, `0 ≤ s < L`):

```
alpha[t][s] = log P(E[s] | frame t) + logSumExp(
    alpha[t-1][s],           // stay at same label
    alpha[t-1][s-1],         // advance from previous label
    alpha[t-1][s-2]          // skip blank (only if E[s] ≠ blank and E[s] ≠ E[s-2])
)
```

The skip-blank transition allows jumping directly from one phoneme to the next when the model is confident. The condition `E[s] != E[s-2]` prevents skipping blanks between consecutive identical phonemes (geminates) — those must pass through a blank.

All arithmetic is in log-space using `logSumExp(a, b) = max(a,b) + log(exp(a−max) + exp(b−max))` for numerical stability.

### 5.2 CTC Backward Pass (Beta)

`beta[t][s]` is the log probability of generating the suffix `E[s..L-1]` in frames `t..T-1`, given we are in state `s` at frame `t`.

**Initialization:**
```
beta[T-1][L-1] = 0.0   (log probability 1)
beta[T-1][L-2] = 0.0   (sequence can end at last blank or last phoneme)
```

**Recurrence** (traversed in reverse, `t` from `T-2` down to `0`):

```
beta[t][s] = logSumExp(
    beta[t+1][s]   + log P(E[s]   | frame t+1),   // stay
    beta[t+1][s+1] + log P(E[s+1] | frame t+1),   // advance
    beta[t+1][s+2] + log P(E[s+2] | frame t+1)    // skip blank (conditional)
)
```

### 5.3 GOP Score Calculation from Posterior Gamma

The total sequence log-probability is:
```
P_total = logSumExp(alpha[T-1][L-1], alpha[T-1][L-2])
```

The posterior probability (gamma) of being in phoneme state `s = 2k+1` at frame `t` is:
```
gamma(t, s) = exp( alpha[t][s] + beta[t][s] − P_total )
```

For each target phoneme `k`, the GOP score is computed as the **gamma-weighted expected log-probability**, normalized by the maximum log-probability across the vocabulary at each frame. This normalization converts the raw log-probability into a relative confidence — comparing the target phoneme's probability to the best possible phoneme at that moment in the utterance:

```swift
let gamma    = alpha[t][s] + beta[t][s] - pTotal
let gammaLin = exp(gamma)
let logP     = log(max(probs[t * vocabSize + E[s]], 1e-8))

// maxLogP = log probability of the best phoneme at this frame
sumGammaLin += gammaLin
sumLogP     += gammaLin * (logP - maxLogP)
```

Final score (exponentiate the weighted average):
```swift
let score = sumGammaLin > 0.001 ? exp(sumLogP / sumGammaLin) : 0.0
```

This produces a value in `[0, 1]`:
- **~1.0** — the target phoneme was the most probable phoneme at every frame weighted by alignment posterior. Perfect pronunciation.
- **~0.0** — the target phoneme was never competitive at any aligned frame. Severe mispronunciation.

The `frames` count is estimated as `round(sumGammaLin)` — the expected number of audio frames the model attributed to this phoneme.

### 5.4 Geminate Post-Processing

When the target sequence contains **consecutive identical phonemes** (geminates, e.g., "night time" → `t t`), CTC alignment is ambiguous: the blank between them is optional, and the forward-backward algorithm distributes probability across both positions. This inflates the score of one and deflates the other.

The post-processor detects runs of identical symbols and assigns the **maximum score** in the run to all members:

```swift
while i < metrics.count {
    var j = i + 1
    while j < metrics.count && metrics[j].symbol == metrics[i].symbol { j += 1 }
    if j > i + 1 {
        let maxScore = metrics[i..<j].map { $0.gopScore }.max() ?? 0.0
        // assign maxScore to all phonemes in [i, j)
    }
    i = j
}
```

### 5.5 Word Score Aggregation

After phoneme scoring, word-level scores are computed in `PhonemeInferenceViewModel`. Each `WordScore` collects the `PhoneScore` objects for its constituent phonemes and averages their GOP scores:

```swift
let avg = scoresForWord.isEmpty ? 0.0
    : scoresForWord.map { $0.gopScore }.reduce(0, +) / Float(scoresForWord.count)
return WordScore(word: alignment.word, phoneScores: scoresForWord, averageScore: avg)
```

The mapping from phonemes to words is provided by `PhonemeWordAligner.alignHybrid(...)` — each word contains its `phonemeIndices`, which index into the flat `extractedPhonemes` array.

---

## 6. Full End-to-End Orchestration

**File:** `ViewModels/PhonemeInferenceViewModel.swift`

The ViewModel drives all state transitions. Below is the complete call chain for each phase.

### Phase 1: `generateBaseline()`

```
1. QwenTTSService.shared.generateAudio(text, referenceAudioURL, ...)
   ├─ [internal] trimAudio(referenceAudioURL, maxSeconds)     → trimmedRefURL
   ├─ [internal] loadAudioArray(trimmedRefURL)                → refAudioArray
   ├─ [internal] SharedSTTService.transcribe(trimmedRefURL)   → refText
   ├─ model.generateStream(text, refAudio, refText, ...)
   │   └─ per chunk: fade-in, accumulate, player.scheduleBuffer()
   └─ AudioUtils.writeWavFile(allFloats)                      → native_baseline.wav

2. AudioRecordingService.trimSilenceAndDenoise(native_baseline.wav)
   └─ VAD trim + 80Hz highpass                               → baseline_preprocessed.wav

3. AudioRecordingService.normalizeTempo(baseline_preprocessed.wav, targetWPM: 130)
   └─ AVAudioUnitTimePitch offline render                    → processed audio

4. AudioService.loadAudio(processed audio)
   └─ resample 16kHz + mean/variance normalize               → MLMultiArray [1, N]

5. AudioInferenceEngine.extractTargetPhonemes(MLMultiArray)
   ├─ Wav2Vec2 forward pass                                   → logits [1, T, V]
   └─ runGreedyDecodeWithFrames(logits)                       → [(symbol, frame)]

6. SpeechAlignmentService.getWordTimings(baseline_preprocessed.wav, locale)
   └─ SFSpeechRecognizer on-device                           → [WordTiming]

7. SpeechAlignmentService.alignTimingsToTarget(targetScript, asrTimings)
   └─ Needleman-Wunsch char alignment                        → [WordTiming] (aligned)

8. PhonemeWordAligner.alignHybrid(targetScript, asrTimings, phonemesWithFrames)
   └─ Hybrid DP (phonetic similarity + temporal penalty)     → [(word, phonemeIndices)]
```

### Phase 2: `stopRecordingAndScore()` / `scoreUploadedAudio()`

```
1. AudioRecordingService captures user speech at 16kHz mono   → user_speech_raw.wav

2. AudioRecordingService.normalizeTempo(user_speech_raw.wav, targetWPM: 125)
   └─ AVAudioUnitTimePitch offline render                    → normalized audio

3. AudioService.loadAudio(normalized audio)
   └─ resample 16kHz + mean/variance normalize               → MLMultiArray [1, N]

4. AudioInferenceEngine.extractUserLogits(MLMultiArray)
   └─ Wav2Vec2 forward pass                                   → raw logits [1, T, V]

5. AudioInferenceEngine.runGreedyDecodeWithFrames(logits)
   └─ display-only greedy decode                             → userRawPhonemes

6. AlignmentScorerEngine.scorePronunciation(
       userLogits, targetPhonemes, vocabulary, greedyAnchors)
   ├─ MathService.softmaxVectorized(logits)                  → probs [T × V]
   ├─ CTC forward pass (alpha matrix)
   ├─ CTC backward pass (beta matrix)
   ├─ gamma-weighted GOP computation per phoneme
   └─ geminate post-processing                               → [PhoneScore]

7. Aggregate PhoneScore → WordScore via targetWordAlignments  → [WordScore]
```

---

## 7. Data Flow Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                       PHASE 1: BASELINE                            │
│                                                                    │
│  Target Script ──► QwenTTSService ──► native_baseline.wav          │
│       ▲                 ▲                      │                   │
│  Reference WAV ──► Whisper STT (MLX)           ▼                   │
│  (trimmed, ~5-9s)   (refText)     trimSilenceAndDenoise            │
│                                               │                    │
│                                  baseline_preprocessed.wav         │
│                                               │                    │
│                                  ┌────────────┴───────────┐        │
│                                  ▼                        ▼        │
│                            normalizeTempo         SFSpeechRecognizer│
│                            (130 WPM target)        (on-device ASR) │
│                                  │                        │        │
│                        AudioService.loadAudio    alignTimingsToTarget
│                        (16kHz + z-norm)          (NW char alignment)│
│                                  │                        │        │
│                        Wav2Vec2 (CoreML)        [WordTiming] ──┐   │
│                        cpuAndGPU                               │   │
│                                  │                             │   │
│                       [(symbol, frame)]                        │   │
│                                  └──────────► alignHybrid ◄───┘   │
│                                          (Hybrid DP: similarity     │
│                                           + temporal penalty)       │
│                                               │                    │
│                                  [(word, phonemeIndices)]           │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│                    PHASE 2: USER EVALUATION                        │
│                                                                    │
│  Microphone ──► 16kHz mono WAV ──► normalizeTempo (125 WPM)        │
│                                           │                        │
│                                 AudioService.loadAudio             │
│                                 (16kHz + z-norm)                   │
│                                           │                        │
│                                 Wav2Vec2 (CoreML)                  │
│                                           │                        │
│                               raw logits [1, T, V]                 │
│                                           │                        │
│                             AlignmentScorerEngine                  │
│                target phonemes ──────────►│◄── vocabulary          │
│                (from Phase 1)             │                        │
│                                     softmax → probs                │
│                                     CTC forward (alpha)            │
│                                     CTC backward (beta)            │
│                                     gamma posterior                │
│                                     GOP per phoneme                │
│                                     geminate fix                   │
│                                           │                        │
│                                     [PhoneScore]                   │
│                                           │                        │
│                 word alignments ─────────►│                        │
│                 (from Phase 1)       [WordScore]                   │
│                                           │                        │
│                                        Display                     │
└────────────────────────────────────────────────────────────────────┘
```

---

## 8. Key File Reference

| File | Layer | Responsibility |
|------|-------|----------------|
| `Services/MLXTTSService.swift` | TTS | QwenTTS model loading, streaming inference, reference audio smart-trimming, 150ms fade-in, WAV export, TTFA/RTF measurement |
| `Services/SharedSTTService.swift` | STT | Whisper (MLX) singleton for transcribing reference audio to `refText` |
| `Services/TTSServiceProtocol.swift` | Protocol | `TTSServiceProtocol` actor protocol, `TTSRefLength` enum (Short/Medium/Long, 5/7/9s) |
| `Services/AudioRecordingService.swift` | Audio I/O | Microphone capture (16kHz mono), VAD silence trim, 80Hz highpass denoise, WPM-based tempo normalization |
| `Services/AudioService.swift` | Audio Preprocessing | 16kHz resample, Wav2Vec2 mean/variance z-normalization, `MLMultiArray` conversion; `AudioStreamPlayer` for real-time chunk playback |
| `Services/MathService.swift` | Math | Vectorized per-frame softmax via Accelerate (`vDSP_vsadd`, `vvexpf`, `vDSP_vsdiv`) |
| `Evaluation/AudioInferenceEngine.swift` | Evaluation | CoreML Wav2Vec2 wrapper, greedy CTC decode with frame indices, raw logit extraction, hardcoded IPA vocabulary |
| `Evaluation/SpeechAlignmentService.swift` | Alignment | Apple `SFSpeechRecognizer` word timings (on-device), Needleman-Wunsch char-level ASR→script timing reconciliation |
| `Evaluation/PhonemeWordAligner.swift` | Alignment | Hybrid DP phoneme-to-word assignment: phonetic similarity table, temporal anchoring, coarticulation sharing, Chinese Pinyin support |
| `Evaluation/AlignmentScorerEngine.swift` | Scoring | CTC forward-backward algorithm, gamma posterior, GOP score with max-normalized log-prob, geminate run post-processing |
| `ViewModels/PhonemeInferenceViewModel.swift` | Orchestration | Full pipeline coordination across both phases, published state management, UI binding |

---

*This guide covers the production pipeline as implemented. CosyVoice integration was evaluated and excluded due to reliability concerns during the MLX native port phase; see `docs/journal.md` for background.*
