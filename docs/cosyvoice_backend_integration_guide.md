# CosyVoice Backend Integration Guide

> **Audience**: This document is written for any client team integrating against the CosyVoice TTS backend.  
> It covers the full pipeline architecture, every exposed API endpoint, request/response contracts, and a worked integration example modelled on the Swift reference implementation.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Running the Server](#3-running-the-server)
4. [API Reference](#4-api-reference)
   - [GET /health](#get-health)
   - [GET /voices_list](#get-voices_list)
   - [GET /voices/{filename}](#get-voicesfilename)
   - [POST /generate](#post-generate)
5. [Integration Pipeline — Step by Step](#5-integration-pipeline--step-by-step)
   - [Step 1 — Server Health Check](#step-1--server-health-check)
   - [Step 2 — Reference Audio Selection & On-Client Trimming](#step-2--reference-audio-selection--on-client-trimming)
   - [Step 3 — Building the Multipart Request](#step-3--building-the-multipart-request)
   - [Step 4 — Receiving Audio & Parsing Pace Metadata](#step-4--receiving-audio--parsing-pace-metadata)
6. [Server-Side Processing Details](#6-server-side-processing-details)
   - [Reference Audio Transcription](#reference-audio-transcription)
   - [Pace Normalization Algorithm](#pace-normalization-algorithm)
   - [Dynamic Model Routing](#dynamic-model-routing)
7. [Response Headers Reference](#7-response-headers-reference)
8. [Language & Model Routing Reference](#8-language--model-routing-reference)
9. [Reference Length Guide](#9-reference-length-guide)
10. [Swift Reference Implementation](#10-swift-reference-implementation)
11. [Web / JavaScript Reference Implementation](#11-web--javascript-reference-implementation)
12. [Error Handling](#12-error-handling)
13. [Known Limitations & Notes](#13-known-limitations--notes)

---

## 1. System Overview

The CosyVoice backend is a **FastAPI** server (`cosy_sandbox/main.py`) that exposes a REST API for zero-shot, voice-cloned text-to-speech synthesis.

**Key design decisions:**
- The client is responsible for **trimming** the reference audio before upload. This moves the reference-length selection logic entirely to the client, keeping the server stateless with respect to voice asset management.
- **All voice assets live on the client.** The server does not store or manage a voice library — it only uses what the client sends in the request.
- Pace normalization (WPM detection, speed adjustment) happens server-side after the reference audio is received. The results are returned as custom HTTP response headers so the client can display them.
- The server spawns a **subprocess** per request to run the MLX TTS pipeline. This isolates MLX metal memory state between calls and prevents GPU state leakage across requests.

**Runtime Environment:**
- Python 3.11+
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) for inference
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) for reference transcription
- Runs on Apple Silicon (Metal backend via MLX)

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENT (Swift / Web)                        │
│                                                                      │
│  1. Select reference voice WAV from local assets                    │
│  2. Trim to target duration (6s / 20s / 30s) — on device           │
│  3. POST /generate  (text + trimmed WAV binary + params)            │
│  4. Receive WAV audio + pace metadata headers                        │
└───────────────────────┬─────────────────────────────────────────────┘
                        │ multipart/form-data
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     FastAPI Server  :8000                            │
│                                                                      │
│  POST /generate                                                      │
│  ├── Save uploaded WAV to temp file                                  │
│  ├── Spawn subprocess (MLX isolation)                                │
│  │    ├── Transcribe ref audio  →  mlx-whisper                      │
│  │    ├── Detect WPM            →  word count / duration            │
│  │    ├── Normalize speed       →  clamp(BASELINE_WPM / WPM, 0.6–1.6) │
│  │    ├── Apply user speed      →  clamp(norm × user_speed, 0.5–2.0) │
│  │    └── Generate audio        →  mlx-audio (CosyVoice 2 or 3)    │
│  └── Return WAV + X-Detected-WPM / X-Norm-Factor / X-Final-Speed   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Running the Server

```bash
cd cosy_sandbox
source .venv/bin/activate  # or: source ../.venv/bin/activate
python main.py
# Server starts at http://localhost:8000
```

Or use the convenience script:

```bash
cd cosy_sandbox && bash run.sh
```

The first generation request will trigger model downloads (~several GB) from Hugging Face via `mlx-audio`. Subsequent calls load from cache.

---

## 4. API Reference

### GET /health

Lightweight liveness probe. Call this before attempting generation to confirm the server is running.

**Request**
```
GET http://localhost:8000/health
```

**Response** `200 OK`
```json
{ "status": "ok" }
```

**Use this to:** Gate your UI on server availability. If this returns a non-200 or times out, show a "Server offline" warning instead of allowing the user to attempt generation.

---

### GET /voices_list

Returns the list of short reference voice filenames available in the server's own `VoiceResources` directory. This is used by the **web UI** to populate a voice picker. 

> **Note for Swift / mobile clients:** Because the reference audio is uploaded as binary by the client, you do not need to call this endpoint. Manage your own list of bundled voice assets on the client side.

**Request**
```
GET http://localhost:8000/voices_list
```

**Response** `200 OK`
```json
{
  "voices": [
    "dewa_short.wav",
    "gagaz_short.wav",
    "kak_anggi_short.wav",
    "nicholas_short.wav",
    "savio_short.wav",
    "tiara_short.wav"
  ]
}
```

Only filenames ending in `_short.wav` are returned. The `_short` suffix denotes the pre-clipped 6-second version (used exclusively by the web UI).

---

### GET /voices/{filename}

Serves static voice asset files from the server's `VoiceResources` directory. Used by the **web UI** to play a preview of the selected reference voice.

**Request**
```
GET http://localhost:8000/voices/savio_short.wav
```

**Response** `200 OK` — `audio/wav` binary stream.

---

### POST /generate

The core synthesis endpoint. Accepts reference audio as a binary upload and returns synthesized speech as a WAV file.

**Request**

| Header | Value |
|---|---|
| `Content-Type` | `multipart/form-data; boundary=<boundary>` |

**Form Fields**

| Field | Type | Required | Description |
|---|---|---|---|
| `text` | `string` | ✅ | The text to synthesize. No length limit enforced, but very long inputs may time out. |
| `reference_audio` | `file (audio/wav)` | ✅ | The reference voice WAV file to clone from. **Pre-trim this on the client** to your desired duration before uploading. |
| `target_language` | `string` | ❌ | Language routing code. `"auto"` (default) uses CosyVoice 3. `"chinese"` uses CosyVoice 2. See §8. |
| `speed` | `float` | ❌ | User-controlled pace multiplier. Range `0.5 – 2.0`. Default `1.0`. Combined multiplicatively with the server's pace normalization. |

**Response** `200 OK`

| Header/Body | Description |
|---|---|
| `Content-Type: audio/wav` | The generated audio. |
| `X-Detected-WPM` | Words-per-minute measured in the uploaded reference audio. |
| `X-Norm-Factor` | Speed normalization multiplier applied by the server (clamped 0.6–1.6). |
| `X-Final-Speed` | Effective speed sent to the TTS model: `clamp(norm_factor × user_speed, 0.5, 2.0)`. |
| `Access-Control-Expose-Headers` | Set to expose the three `X-` headers to browser clients. |

**Response Errors**

| Status | Cause |
|---|---|
| `400 Bad Request` | `text` field is empty. |
| `500 Internal Server Error` | TTS subprocess crashed, or no audio file was produced. `detail` field in the JSON body contains the error message. |

---

## 5. Integration Pipeline — Step by Step

### Step 1 — Server Health Check

Before exposing generation controls to the user, probe `/health`. If it fails (connection refused, timeout, or non-200), mark the service as unavailable.

```
GET /health  →  { "status": "ok" }
```

**Timeout recommendation:** 3 seconds. The server either responds immediately or isn't running.

---

### Step 2 — Reference Audio Selection & On-Client Trimming

The server expects **pre-trimmed** audio. The amount of reference audio to use is a quality trade-off:

| Duration | Clip length | Effect |
|---|---|---|
| **Short** | 6 seconds | Fast Whisper transcription, lower cloning fidelity |
| **Medium** | 20 seconds | Balanced — recommended default |
| **Long** | 30 seconds | Highest voice similarity, slowest transcription |

**On the client**, load the full reference WAV, read the first `N` seconds of PCM frames, and write them to a temporary file. Upload that trimmed file.

In Swift this is done with `AVAudioFile`:

```swift
let inputFile = try AVAudioFile(forReading: referenceURL)
let format = inputFile.processingFormat
let framesToRead = AVAudioFrameCount(min(maxSeconds * format.sampleRate, Double(inputFile.length)))

guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { ... }
try inputFile.read(into: buffer, frameCount: framesToRead)

let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ref_trimmed.wav")
let outputFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
try outputFile.write(from: buffer)
```

Delete the temporary file after the request completes.

---

### Step 3 — Building the Multipart Request

Send a `multipart/form-data` POST to `/generate`. Include:

| Field | How to send |
|---|---|
| `text` | Plain text form field |
| `reference_audio` | Binary file part, `Content-Type: audio/wav` |
| `target_language` | `"auto"` or `"chinese"` (see §8) |
| `speed` | Float string, e.g. `"1.0"` |

**Example (curl)**
```bash
curl -X POST http://localhost:8000/generate \
  -F "text=The quick brown fox jumps over the lazy dog." \
  -F "reference_audio=@/path/to/trimmed_ref.wav;type=audio/wav" \
  -F "target_language=auto" \
  -F "speed=1.0" \
  --output output.wav \
  --dump-header -
```

**Example (Python / requests)**
```python
import requests

with open("trimmed_ref.wav", "rb") as f:
    response = requests.post(
        "http://localhost:8000/generate",
        data={
            "text": "The quick brown fox jumps over the lazy dog.",
            "target_language": "auto",
            "speed": "1.0",
        },
        files={"reference_audio": ("ref.wav", f, "audio/wav")},
        timeout=300,
    )

response.raise_for_status()

print("Detected WPM:", response.headers.get("X-Detected-WPM"))
print("Norm factor:",  response.headers.get("X-Norm-Factor"))
print("Final speed:",  response.headers.get("X-Final-Speed"))

with open("output.wav", "wb") as out:
    out.write(response.content)
```

**Example (JavaScript / fetch)**
```javascript
const formData = new FormData();
formData.append("text", "The quick brown fox jumps over the lazy dog.");
formData.append("reference_audio", audioBlob, "ref.wav");
formData.append("target_language", "auto");
formData.append("speed", "1.0");

const response = await fetch("http://localhost:8000/generate", {
    method: "POST",
    body: formData,
});

if (!response.ok) {
    const err = await response.json();
    throw new Error(err.detail);
}

const detectedWPM = response.headers.get("X-Detected-WPM");
const normFactor  = response.headers.get("X-Norm-Factor");
const finalSpeed  = response.headers.get("X-Final-Speed");

const blob = await response.blob();
const audioURL = URL.createObjectURL(blob);
```

---

### Step 4 — Receiving Audio & Parsing Pace Metadata

The response body is a raw WAV file (`audio/wav`). Write it to disk or a blob URL before playback.

Additionally, read the three custom response headers to surface pace diagnostics in your UI:

| Header | Type | Example |
|---|---|---|
| `X-Detected-WPM` | float string | `"143.2"` |
| `X-Norm-Factor` | float string | `"0.909"` |
| `X-Final-Speed` | float string | `"0.909"` |

> **Browser clients:** These headers are only accessible if the server's `Access-Control-Expose-Headers` is honoured. The server already sets this. Ensure your fetch client does not strip custom headers.

**Computing RTF on the client**

The server does not return RTF — compute it on the client:

```
RTF = total_generation_wall_time / audio_duration_seconds
```

Use your platform's audio file reader to get the exact duration from the returned WAV rather than estimating from byte count, since sample rate can vary.

---

## 6. Server-Side Processing Details

### Reference Audio Transcription

After receiving the uploaded reference WAV, the server runs it through **mlx-whisper** (`mlx-community/whisper-turbo`) to produce a text transcript. This transcript is used in two ways:
1. As the `ref_text` argument to the CosyVoice TTS model (required for zero-shot voice cloning)
2. As the source for word-count-based pace detection

Because Whisper is run inside the isolated subprocess, it shares the same MLX metal context as the TTS model and does not interfere with the FastAPI event loop.

### Pace Normalization Algorithm

The server normalizes the TTS output speed based on the measured speaking rate of the reference voice, targeting a baseline of **130 WPM**.

```
detected_wpm  = word_count(transcript) / (audio_duration_seconds / 60)
norm_factor   = clamp(130.0 / detected_wpm, 0.6, 1.6)
final_speed   = clamp(norm_factor × user_speed, 0.5, 2.0)
```

The purpose of this normalization: if the reference speaker is fast (e.g. 200 WPM), CosyVoice would inherit that pace in the output. The norm factor slows it down toward 130 WPM so the synthesized speech is intelligible regardless of the reference speaker's natural rate. The user's `speed` slider then applies on top of this normalized baseline.

**Clamping ranges:**

| Parameter | Min | Max |
|---|---|---|
| `norm_factor` | 0.6 | 1.6 |
| `final_speed` | 0.5 | 2.0 |

### Dynamic Model Routing

The `target_language` field selects which underlying model is used:

| `target_language` value | Model used | Reason |
|---|---|---|
| `"auto"` (default) | `Fun-CosyVoice3-0.5B-2512-8bit` | Best prosody, zero-shot cloning, multilingual |
| `"chinese"` | `CosyVoice2-0.5B-8bit` | Avoids cross-lingual hallucinations on Mandarin-only content |

Both models are fetched from the `mlx-community` HuggingFace organization.

---

## 7. Response Headers Reference

| Header | Description | Range |
|---|---|---|
| `X-Detected-WPM` | Words per minute measured in the reference audio via Whisper | Typically 80–220 for natural speech |
| `X-Norm-Factor` | Multiplicative speed correction to reach 130 WPM baseline | 0.6 – 1.6 |
| `X-Final-Speed` | Actual speed value passed to the TTS model | 0.5 – 2.0 |

These are diagnostic metadata. They are not required for playback but are useful for surfacing pace analysis to the end user.

---

## 8. Language & Model Routing Reference

Map your UI's language selection to the `target_language` field value as follows:

| UI label | `target_language` to send | Model selected |
|---|---|---|
| Auto-Select | `"auto"` | CosyVoice 3 |
| English | `"auto"` | CosyVoice 3 |
| Mandarin | `"chinese"` | CosyVoice 2 |

Only `"auto"` and `"chinese"` are recognized by the server. Any other string is treated as `"auto"`.

---

## 9. Reference Length Guide

Client-side trimming durations and their trade-offs:

| Label | `maxSeconds` | Whisper transcription time | Voice cloning fidelity | Recommended for |
|---|---|---|---|---|
| Short | 6 | Fast (~1–2s) | Lower — fewer prosody cues | Quick previews, testing |
| Medium | 20 | Moderate (~3–5s) | Good | Default for production use |
| Long | 30 | Slower (~5–8s) | Highest | Maximum voice similarity, formal content |

> The server does not know which reference length the client chose — it simply processes whatever duration is uploaded. Label your UI controls accordingly so users understand the trade-off.

---

## 10. Swift Reference Implementation

The Swift integration lives in:
- [`CosyVoiceTTSService.swift`](../PhonemeInferenceSandbox/PhonemeInferenceSandbox/CosyVoiceTTSService.swift) — HTTP client, audio trimming, multipart encoding, header parsing
- [`PhonemeInferenceViewModel.swift`](../PhonemeInferenceSandbox/PhonemeInferenceSandbox/PhonemeInferenceViewModel.swift) — Orchestration, language mapping, state management
- [`ContentView.swift`](../PhonemeInferenceSandbox/PhonemeInferenceSandbox/ContentView.swift) — UI, parameter controls, metrics display

### Key types

```swift
/// Controls how much reference audio is trimmed and uploaded.
public enum CosyRefLength: String, CaseIterable {
    case short  // 6 seconds
    case medium // 20 seconds
    case long   // 30 seconds
}

/// Returned by generateAudio() — wraps all result data.
public struct CosyVoiceResult {
    public let audioURL: URL
    public let ttfa: Double       // Time-to-first-audio (s)
    public let rtf: Double        // Real-time factor
    public let detectedWPM: Double?
    public let normFactor: Double?
    public let finalSpeed: Double?
}
```

### Calling the API from Swift

```swift
let result = try await CosyVoiceTTSService.shared.generateAudio(
    text: "The quick brown fox jumps over the lazy dog.",
    referenceAudioURL: URL(fileURLWithPath: "/path/to/savio.wav"),
    language: "auto",    // or "chinese" for Mandarin
    speed: 1.0,
    refLength: .medium
)

// result.audioURL  — local temp WAV path, ready to play
// result.ttfa      — latency metric
// result.rtf       — speed metric  
// result.detectedWPM, result.normFactor, result.finalSpeed — pace diagnostics
```

### Language mapping helper (Swift)

```swift
func cosyLanguageCode(for uiLanguage: String) -> String {
    switch uiLanguage {
    case "Mandarin": return "chinese"
    default:         return "auto"
    }
}
```

### Health check (Swift)

```swift
public func initialize() async throws {
    let url = URL(string: "http://localhost:8000/health")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 3.0

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw MyError.serverOffline
    }
}
```

---

## 11. Web / JavaScript Reference Implementation

The web UI is served at `http://localhost:8000/` from `cosy_sandbox/static/`.

> **Note:** The web UI (`app.js`) currently uses a legacy API variant that passes a `reference_voice` filename string instead of a binary file upload. This works only because the server's own voice library is used. New integrations should follow the binary-upload pattern documented in §5.

**Working web client pattern (updated):**

```javascript
// 1. Fetch the WAV blob from your asset server / local file input
const response = await fetch("/voices/savio_short.wav");
const audioBlob = await response.blob();

// 2. Build the multipart request
const formData = new FormData();
formData.append("text",             "Hello, world.");
formData.append("reference_audio",  audioBlob, "ref.wav");
formData.append("target_language",  "auto");
formData.append("speed",            "1.0");

// 3. Call /generate
const res = await fetch("/generate", { method: "POST", body: formData });
if (!res.ok) throw new Error((await res.json()).detail);

// 4. Read pace headers (requires CORS expose-headers — already set by server)
console.log("WPM:",   res.headers.get("X-Detected-WPM"));
console.log("Norm:",  res.headers.get("X-Norm-Factor"));
console.log("Speed:", res.headers.get("X-Final-Speed"));

// 5. Play audio
const blob = await res.blob();
document.querySelector("audio").src = URL.createObjectURL(blob);
```

---

## 12. Error Handling

### Client-side recommendations

| Scenario | Recommended behavior |
|---|---|
| `/health` timeout or connection refused | Show "CosyVoice server offline" warning. Do not expose generate controls. |
| `POST /generate` → 400 | Validate that `text` is non-empty before sending. |
| `POST /generate` → 500 | Display `response.detail` to the user. Common causes: MLX model not downloaded yet, out-of-memory on the GPU. |
| Request timeout (> 300s) | The server may be processing a very long text or the subprocess crashed silently. Retry or reduce text length. |

### Server error response format

On any error, the server returns:
```json
{ "detail": "Human-readable error message." }
```

---

## 13. Known Limitations & Notes

- **Synchronous per request:** Each `/generate` call blocks until the subprocess completes. The server does not support concurrent generation — requests queue behind one another.
- **No streaming:** The full WAV is returned as a single response body. There is no chunked/streaming audio delivery.
- **Apple Silicon only:** The MLX backend requires Apple Silicon hardware. The server cannot run on x86 or non-Apple GPUs.
- **Cold start:** The first request after server startup triggers model loading, which can take 30–60 seconds depending on cache state.
- **Temp file cleanup:** The server cleans up the uploaded reference audio temp file after each request. Generated output WAVs in `temp_outputs/` are not automatically deleted and will accumulate over time.
- **Web UI compatibility:** The existing `static/app.js` web UI uses the old `reference_voice` string field. It will not work with the current `/generate` endpoint until updated to use binary file upload per §11.
