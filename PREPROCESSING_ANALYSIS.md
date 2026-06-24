# Audio TTS Preprocessing Analysis

**Date:** 2026-06-23
**Dataset:** Emotional Speech Dataset (dataset_dropbox/)
**Purpose:** Voice cloning for TTS models

---

## Dataset Overview

### Structure
- **Location:** `dataset_dropbox/`
- **Speakers:** 10 (IDs: 0011-0020)
- **Total Files:** ~17,500 WAV files
- **Emotions per Speaker:** 5 (Angry, Happy, Neutral, Sad, Surprise)
- **Format:** 16-bit PCM, Mono, 16kHz

### File Organization
```
dataset_dropbox/
├── 0011/
│   ├── 0011.txt              # Transcripts: [id]\t[text]\t[emotion]
│   ├── Angry/                # ~350 WAV files
│   ├── Happy/                # ~350 WAV files
│   ├── Neutral/              # ~350 WAV files
│   ├── Sad/                  # ~350 WAV files
│   └── Surprise/             # ~350 WAV files
├── 0012/
│   └── ...
...
└── 0020/
```

---

## TTS Model Comparison

| Feature | Qwen3-TTS | StyleTTS2 | CosyVoice2 |
|---------|-----------|-----------|------------|
| **Sample Rate** | 24kHz | 24kHz | 24kHz |
| **Training Data Needed** | 10-30 min per speaker | 5-10 hours per speaker | 3-10s for cloning |
| **Duration Range** | 3-15s (optimal: 10-15s) | 2-10s | 3-10s |
| **Emotion Control** | Prompt-based | Manual slider/reference | Prompt-based |
| **Output Format** | JSONL | TXT (pipe-delimited) | JSONL |
| **Training Approach** | Fine-tune pre-trained | Train from scratch | Zero-shot cloning |
| **Best For** | Quick voice adaptation | High control, quality | Minimal data cloning |

---

## Preprocessing Requirements

### Common for All Models
1. **Audio Quality**
   - Resample to 24kHz
   - Remove clipped audio (peak > 0.99)
   - Filter low SNR (< 10dB)
   - Ensure clean, continuous speech

2. **Duration Filtering**
   - Remove clips that are too short (< 1-3s)
   - Remove clips that are too long (> 10-15s)
   - Focus on optimal ranges per model

3. **Text Alignment**
   - Match audio files with transcripts
   - Verify transcript accuracy
   - Maintain speaker-text pairs

### Model-Specific Requirements

#### Qwen3-TTS
- **Audio Requirements:**
  - 24kHz, 16-bit, mono
  - 3-15 seconds per clip (10-15s optimal)
  - Clean speech, minimal background noise

- **Data Format:**
  ```json
  {"audio": "path/to/file.wav", "text": "transcript", "ref_audio": "path/to/reference.wav"}
  ```

- **Special Notes:**
  - Use same `ref_audio` for all clips (improves consistency)
  - Requires tokenization step (prepare_data.py)
  - Pre-trained model available for fine-tuning
  - Only 10-30 min of YOUR voice needed later

#### StyleTTS2
- **Audio Requirements:**
  - 24kHz, 16-bit, mono
  - 2-10 seconds per clip
  - MOS (Mean Opinion Score) > 2.5

- **Data Format:**
  ```
  /path/to/file.wav|transcript text|speaker_id
  ```

- **Special Notes:**
  - Requires train/val split (typically 80/20)
  - Need OOD (out-of-distribution) data for adversarial training
  - More control over prosody and style
  - Requires ~5-10 hours of YOUR voice

#### CosyVoice2
- **Audio Requirements:**
  - 24kHz, 16-bit, mono
  - 3-10 seconds per clip
  - Active speech > 60% of duration
  - Max 2s continuous silence

- **Data Format:**
  ```json
  {"audio_path": "path/to/file.wav", "text": "transcript", "speaker": "speaker_id", "emotion": "Neutral"}
  ```

- **Special Notes:**
  - Easiest for voice cloning (only 3-10s needed)
  - Can use prompt-based emotion control
  - No training required for basic cloning
  - Just 3-10s of YOUR voice needed!

---

## Recommended Preprocessing Pipeline

### Phase 1: Quality Analysis
1. Scan all audio files and parse transcripts
2. Calculate audio metrics:
   - Duration
   - Sample rate
   - RMS energy
   - Peak amplitude (clipping detection)
   - Speech-to-silence ratio
   - SNR (Signal-to-Noise Ratio)

### Phase 2: Filtering
Apply model-specific filters:
- Duration: 3-15s for Qwen3-TTS, 2-10s for StyleTTS2, 3-10s for CosyVoice2
- Remove clipped audio
- Remove low SNR audio (< 10dB)
- For CosyVoice2: Ensure speech ratio > 60%

### Phase 3: Audio Processing
1. Resample all audio from 16kHz → 24kHz
2. Save in organized structure:
   ```
   preprocessed_data/
   ├── qwen3_tts_audio/
   │   ├── 0011/Neutral/*.wav
   │   ├── 0012/Neutral/*.wav
   │   └── ...
   ├── 0011_qwen3_tts.jsonl
   ├── 0012_qwen3_tts.jsonl
   └── qwen3_tts_metadata.csv
   ```

### Phase 4: Format Conversion
- Generate model-specific output files (JSONL/TXT)
- Create metadata CSV with all audio features
- Generate feature analysis report

---

## Emotion Handling Strategy

### Recommendation: Keep Emotions Separate

**Why?**
1. **For Voice Cloning:** "Neutral" emotion provides most natural baseline voice
2. **Flexibility:** Can later experiment with emotional styles
3. **Model Requirements:**
   - Qwen3-TTS & CosyVoice2: Can control emotion via prompts at inference
   - StyleTTS2: Needs emotional reference clips

**Approach:**
1. **Start with Neutral only** for initial training
2. Keep other emotions available for:
   - Reference audio (StyleTTS2)
   - Fine-tuning emotional variants later
   - Testing emotional prompt control

---

## Computing Resource Options

### Option 1: CPU-Only (librosa)
**Pros:**
- No GPU required
- Simple setup: `pip install librosa soundfile`
- Works on any machine

**Cons:**
- Slower processing (~2-3x slower)
- For 17,500 files: ~2-4 hours total

**Recommended for:**
- Machines without GPU
- One-time preprocessing

### Option 2: GPU-Accelerated (torchaudio)
**Pros:**
- 2-3x faster than CPU
- Better for large datasets
- Reusable for model training

**Cons:**
- Requires PyTorch with CUDA
- Needs GPU (NVIDIA)

**Recommended for:**
- Machines with GPU
- Repeated preprocessing runs

---

## Expected Output

### After Running Preprocessing Notebook:

#### For Qwen3-TTS (TARGET_MODEL = 'qwen3_tts'):
```
preprocessed_data/
├── qwen3_tts_audio/
│   ├── 0011/Neutral/*.wav (24kHz)
│   ├── 0012/Neutral/*.wav
│   └── ...
├── 0011_qwen3_tts.jsonl          # Training data format
├── 0012_qwen3_tts.jsonl
├── ...
├── qwen3_tts_metadata.csv        # Full feature analysis
└── qwen3_tts_analysis.png        # Visualization (if matplotlib available)
```

#### Metadata CSV Columns:
- `file_path`: Original audio path
- `processed_path`: Resampled 24kHz audio path
- `speaker_id`: Speaker ID (0011-0020)
- `emotion`: Emotion label
- `file_id`: Unique file identifier
- `transcript`: Text transcript
- `duration`: Audio length (seconds)
- `sample_rate`: Original sample rate
- `rms`: RMS energy
- `peak_amp`: Peak amplitude
- `is_clipped`: Clipping detected (True/False)
- `speech_ratio`: Active speech ratio (0-1)
- `snr_db`: Signal-to-Noise Ratio (dB)

---

## Next Steps After Preprocessing

### For Qwen3-TTS:
1. **Install Qwen3-TTS:**
   ```bash
   git clone https://github.com/QwenLM/Qwen3-TTS.git
   cd Qwen3-TTS
   pip install -r requirements.txt
   ```

2. **Tokenize Audio** (encode to discrete codes):
   ```bash
   python finetuning/prepare_data.py \
     --input preprocessed_data/0011_qwen3_tts.jsonl \
     --output tokenized_data/
   ```

3. **Fine-tune Model:**
   ```bash
   python finetuning/finetune.py \
     --model Qwen/Qwen3-TTS-12Hz-0.6B-Base \
     --data tokenized_data/ \
     --output checkpoints/
   ```

4. **For YOUR Voice Later:**
   - Record 10-30 min of clean speech (neutral tone)
   - Update `DATASET_PATH` to your recordings folder
   - Re-run preprocessing notebook
   - Fine-tune on your voice

### For StyleTTS2:
1. Install StyleTTS2
2. Split data into train/val lists (80/20)
3. Update config.yml with paths
4. Train with: `python train.py --config config.yml`

### For CosyVoice2:
1. Install CosyVoice
2. Process voice features: `python process_prompt.py`
3. **For YOUR Voice:** Only need 3-10s recording!
   - Record 3-10s of clean speech
   - Use as reference audio
   - No training needed for basic cloning

---

## Feature Analysis (Expected Results)

### Duration Distribution
- Most clips: 2-5 seconds
- After filtering (3-15s): ~80-90% retained
- Optimal clips (10-15s): ~10-20% of dataset

### Audio Quality
- **SNR:** Expected mean ~15-25 dB (good quality)
- **Speech Ratio:** Expected ~70-85% active speech
- **Clipping:** Expected <1% clipped files

### Per-Speaker Statistics
- Each speaker: ~3,500 total files
- After filtering (Neutral only): ~350 files per speaker
- Total audio per speaker: ~15-30 minutes (Neutral)
- **Perfect for Qwen3-TTS fine-tuning!**

### Per-Emotion Distribution
- Balanced: ~3,500 files per emotion
- Neutral recommended for voice cloning training
- Other emotions: Available for reference/experimentation

---

## Frequently Asked Questions

### Q1: Which model should I use?
**A:** For cloning YOUR voice with minimal data:
- **CosyVoice2** (only 3-10s needed, no training)
- **Qwen3-TTS** (10-30 min needed, quick fine-tuning)
- **StyleTTS2** (5-10 hours needed, best quality/control)

### Q2: Do I need to record my own voice now?
**A:** No! Train on this dataset (10 speakers) first to learn the pipeline. Later, record 10-30 min of your voice and re-run preprocessing.

### Q3: Can I train on all emotions?
**A:** Possible, but not recommended initially:
- Start with "Neutral" for natural voice baseline
- Qwen3-TTS/CosyVoice2 can add emotion via prompts later
- StyleTTS2 can use emotional clips as references

### Q4: How long does preprocessing take?
- **CPU (librosa):** ~2-4 hours for full dataset
- **GPU (torchaudio):** ~1-2 hours for full dataset
- **Per speaker only:** ~15-30 minutes

### Q5: What if I don't have a GPU?
**A:** Use CPU-only mode (librosa). It's slower but works perfectly. Consider:
- Processing overnight
- Processing one speaker at a time
- Using cloud GPU (Colab, Kaggle)

### Q6: Do I need all 10 speakers?
**A:** No! For learning:
- Start with 1-2 speakers
- Test the pipeline
- Scale to all speakers once confirmed working

---

## Preprocessing Checklist

- [ ] Install dependencies: `pip install librosa soundfile torchaudio tqdm pandas numpy scipy matplotlib`
- [ ] Verify dataset path exists: `dataset_dropbox/`
- [ ] Choose target model: Set `TARGET_MODEL` in notebook (qwen3_tts/styletts2/cosyvoice2)
- [ ] (Optional) Adjust emotion filter: Edit `keep_emotions` config
- [ ] (Optional) Adjust duration ranges: Edit `min_duration`/`max_duration`
- [ ] Run preprocessing notebook (don't execute all cells at once, run step-by-step)
- [ ] Review feature analysis report
- [ ] Check output files in `preprocessed_data/`
- [ ] Proceed with model-specific training steps

---

## Summary

This preprocessing pipeline prepares your emotional speech dataset for TTS voice cloning across three popular models:

1. **Qwen3-TTS:** Best balance of data requirements (10-30 min) and quality
2. **StyleTTS2:** Best quality/control but needs most data (5-10 hours)
3. **CosyVoice2:** Easiest for cloning with minimal data (3-10 seconds)

**Recommendation for your use case:**
- Train on current dataset (10 speakers) with **Qwen3-TTS**
- Learn the pipeline end-to-end
- Later record 10-30 min of your own voice
- Fine-tune Qwen3-TTS on your voice for personalized TTS

The notebook handles:
- ✓ Dataset path configuration
- ✓ Automatic quality analysis
- ✓ Model-specific filtering
- ✓ Audio resampling (16kHz → 24kHz)
- ✓ Format conversion (JSONL/TXT)
- ✓ Feature analysis & visualization
- ✓ CPU and GPU processing modes

**Ready to start!** Open `preprocess.ipynb` and run cells sequentially.
