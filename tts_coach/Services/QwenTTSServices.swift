//
//  QwenTTSServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

//import Foundation
//import Combine
//import MLX
//import Hub
//import Qwen3TTS
//
///// Fully on-device, no-API text-to-speech via Apple's MLX framework.
/////
///// Uses `AtomGradient/swift-qwen3-tts`, **not** `mlx-audio-swift`
///// (Blaizzy). Switched after isolating a real bug in the latter: its
///// generic `generate(text:voice:refAudio:refText:language:)` ignored
///// `text` entirely in voice-cloning mode (refAudio+refText given),
///// always speaking back `refText`'s content instead. Confirmed with a
///// controlled diagnostic: plain generation with no cloning correctly
///// spoke arbitrary new text; cloning generation, same text, always
///// spoke the enrollment script verbatim, full file, no trace of the
///// new text anywhere in it. No matching issue was found on Blaizzy's
///// tracker as of this writing.
/////
///// `swift-qwen3-tts` exposes voice cloning as its own dedicated method
///// (`generateVoiceClone`) instead of one overloaded `generate()`
///// handling every mode, so the same bug class shouldn't apply — but
///// it's a newer, much smaller package (5 stars at time of writing), so
///// treat this as "the most promising fix available" rather than a
///// guarantee. If `generateSpeech` ever starts echoing reference text
///// again, that's the first place to look.
/////
///// ⚠️ Two one-time manual steps before this builds/runs — see the chat
///// message this file was delivered with.
//final class QwenTTSService: ObservableObject {
//
//    enum State: Equatable {
//        case idle
//        case loadingModel
//        case ready
//        case generating
//        case failed(String)
//    }
//
//    @Published private(set) var state: State = .idle
//
//    // "Base" checkpoint — the only model type that supports
//    // `generateVoiceClone`. No 8bit build of Base+Cloning exists for
//    // this package (only the larger bf16 one), unlike the old
//    // Blaizzy-based 8bit model — expect a bigger one-time download.
//    private static let modelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
//
//    private var model: Qwen3TTSModel?
//
//    /// Loads the model if it hasn't been already (downloading it from
//    /// Hugging Face to local storage on first use). Safe to call before
//    /// every generation — it's a no-op once loaded. Exposed publicly so
//    /// a caller can warm the model up ahead of time (e.g. as soon as
//    /// the Voices tab opens) instead of eating the load time on first
//    /// generate.
//    func loadModelIfNeeded() async throws {
//        guard model == nil else { return }
//        state = .loadingModel
//        do {
//            // swift-qwen3-tts only loads from a local directory
//            // (`fromPretrained(_ modelPath: String)`), unlike
//            // mlx-audio-swift which auto-downloaded by repo ID
//            // internally. `Hub.snapshot` (from swift-transformers,
//            // already a transitive dependency) gives us the same
//            // auto-download-to-local-cache behavior explicitly.
//            let modelDir = try await Hub.snapshot(
//                from: Self.modelRepo,
//                progressHandler: { progress in
//                    print("QwenTTSService: downloading model — \(progress.completedUnitCount)/\(progress.totalUnitCount) files")
//                }
//            )
//            try Self.ensureTokenizerJSONExists(in: modelDir)
//            model = try await Qwen3TTSModel.fromPretrained(modelDir.path)
//            state = .ready
//        } catch {
//            state = .failed("Failed to load Qwen3-TTS model: \(error.localizedDescription)")
//            throw error
//        }
//    }
//
//    /// `swift-transformers` currently requires a local `tokenizer.json`,
//    /// but the Qwen3-TTS MLX repos only ship `vocab.json` + `merges.txt`.
//    /// Build the equivalent fast-tokenizer file in the downloaded cache so
//    /// `AutoTokenizer.from(modelFolder:)` can load the model.
//    private static func ensureTokenizerJSONExists(in modelDir: URL) throws {
//        let tokenizerURL = modelDir.appendingPathComponent("tokenizer.json")
//        if FileManager.default.fileExists(atPath: tokenizerURL.path) { return }
//
//        let vocabURL = modelDir.appendingPathComponent("vocab.json")
//        let mergesURL = modelDir.appendingPathComponent("merges.txt")
//        guard FileManager.default.fileExists(atPath: vocabURL.path),
//              FileManager.default.fileExists(atPath: mergesURL.path) else {
//            return
//        }
//
//        let vocabData = try Data(contentsOf: vocabURL)
//        guard let vocab = try JSONSerialization.jsonObject(with: vocabData) as? [String: Any] else {
//            throw NSError(
//                domain: "QwenTTSService",
//                code: -2,
//                userInfo: [NSLocalizedDescriptionKey: "Couldn't read Qwen tokenizer vocabulary."]
//            )
//        }
//
//        let mergesText = try String(contentsOf: mergesURL, encoding: .utf8)
//        let merges = mergesText
//            .components(separatedBy: .newlines)
//            .compactMap { line -> [String]? in
//                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
//                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
//                let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
//                return parts.count == 2 ? parts : nil
//            }
//
//        let tokenizerConfig = try loadTokenizerConfig(from: modelDir)
//        let addedTokens = makeAddedTokens(from: tokenizerConfig, vocab: vocab)
//
//        let tokenizerJSON: [String: Any] = [
//            "version": "1.0",
//            "truncation": NSNull(),
//            "padding": NSNull(),
//            "added_tokens": addedTokens,
//            "normalizer": NSNull(),
//            "pre_tokenizer": [
//                "type": "ByteLevel",
//                "add_prefix_space": false,
//                "trim_offsets": true,
//                "use_regex": true
//            ],
//            "post_processor": NSNull(),
//            "decoder": ["type": "ByteLevel"],
//            "model": [
//                "type": "BPE",
//                "dropout": NSNull(),
//                "unk_token": NSNull(),
//                "continuing_subword_prefix": "",
//                "end_of_word_suffix": "",
//                "fuse_unk": false,
//                "byte_fallback": false,
//                "vocab": vocab,
//                "merges": merges
//            ]
//        ]
//
//        let data = try JSONSerialization.data(withJSONObject: tokenizerJSON, options: [.prettyPrinted, .sortedKeys])
//        try data.write(to: tokenizerURL, options: .atomic)
//        print("QwenTTSService: created missing tokenizer.json from vocab.json + merges.txt")
//    }
//
//    private static func loadTokenizerConfig(from modelDir: URL) throws -> [String: Any] {
//        let configURL = modelDir.appendingPathComponent("tokenizer_config.json")
//        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
//        let data = try Data(contentsOf: configURL)
//        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
//    }
//
//    private static func makeAddedTokens(from tokenizerConfig: [String: Any], vocab: [String: Any]) -> [[String: Any]] {
//        if let decoder = tokenizerConfig["added_tokens_decoder"] as? [String: Any] {
//            return decoder.compactMap { key, value -> [String: Any]? in
//                guard let id = Int(key), var token = value as? [String: Any] else { return nil }
//                token["id"] = id
//                return token
//            }
//            .sorted { lhs, rhs in
//                (lhs["id"] as? Int ?? 0) < (rhs["id"] as? Int ?? 0)
//            }
//        }
//
//        return vocab.compactMap { token, idValue -> [String: Any]? in
//            guard token.hasPrefix("<|"), token.hasSuffix("|>"), let id = numericID(from: idValue) else { return nil }
//            return [
//                "id": id,
//                "content": token,
//                "single_word": false,
//                "lstrip": false,
//                "rstrip": false,
//                "normalized": false,
//                "special": true
//            ]
//        }
//        .sorted { lhs, rhs in
//            (lhs["id"] as? Int ?? 0) < (rhs["id"] as? Int ?? 0)
//        }
//    }
//
//    private static func numericID(from value: Any) -> Int? {
//        if let intValue = value as? Int { return intValue }
//        if let number = value as? NSNumber { return number.intValue }
//        return nil
//    }
//
//    /// Generates speech for `text`, cloned to sound like the voice in
//    /// `referenceAudioURL` (which was read aloud as
//    /// `referenceTranscript`), and writes the result to a fresh .wav
//    /// file in the temp directory, returning its URL. The caller owns
//    /// that file from there — same pattern as `AudioRecorderService`
//    /// handing back temp URLs for the caller to manage.
//    func generateSpeech(
//        text: String,
//        referenceAudioURL: URL,
//        referenceTranscript: String
//    ) async throws -> URL {
//        try await loadModelIfNeeded()
//
//        guard let model else {
//            let error = NSError(
//                domain: "QwenTTSService",
//                code: -1,
//                userInfo: [NSLocalizedDescriptionKey: "Model isn't loaded."]
//            )
//            state = .failed(error.localizedDescription)
//            throw error
//        }
//
//        state = .generating
//        do {
//            // Our recorded reference audio is already preprocessed to
//            // 24kHz (see `AudioPreprocessingConfig.targetSampleRate`),
//            // matching what this model expects — no extra resampling
//            // needed here, unlike the old Blaizzy-based code.
//            let (_, refAudio) = try loadAudioArray(from: referenceAudioURL)
//
//            // `generateVoiceClone` is synchronous (`throws`, not
//            // `async throws`) and can take several seconds — running it
//            // via `Task.detached` keeps it off whatever actor called
//            // `generateSpeech` (typically MainActor-inherited from a
//            // SwiftUI button action) so the UI doesn't lock up while it
//            // runs. If Xcode flags a Sendable/concurrency error on this
//            // closure, the simplest fix is dropping the `Task.detached`
//            // wrapper entirely and calling `model.generateVoiceClone`
//            // directly — `generateSpeech` is already `async`, so that
//            // still compiles, it just no longer explicitly hops off
//            // the caller's actor.
//            let audio = try await Task.detached(priority: .userInitiated) {
//                try model.generateVoiceClone(
//                    text: text,
//                    referenceAudio: refAudio,
//                    referenceText: referenceTranscript,
//                    language: "english"
//                )
//            }.value
//
//            let outputURL = FileManager.default.temporaryDirectory
//                .appendingPathComponent(UUID().uuidString)
//                .appendingPathExtension("wav")
//            try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
//
//            state = .ready
//            return outputURL
//        } catch {
//            state = .failed("Speech generation failed: \(error.localizedDescription)")
//            throw error
//        }
//    }
//
//    /// TEMPORARY DIAGNOSTIC — not used by the app's real flow. Generates
//    /// with the model's plain (non-cloning) path, to sanity-check
//    /// `text:` handling in isolation if this ever needs re-diagnosing.
//    ///
//    /// This replaces an earlier draft of this same method that passed
//    /// `referenceAudio: MLXArray([Float]())` (an empty array) into
//    /// `generateVoiceClone` to fake "no cloning" — that was risky and
//    /// likely to crash, since `generateVoiceClone` expects a real
//    /// reference clip, not an empty one. This version calls the
//    /// package's actual no-cloning entry point (`generate`, which for
//    /// a Base checkpoint falls back to a built-in default voice)
//    /// instead, which is both safe and the architecturally correct way
//    /// to ask for unconditioned generation.
//    ///
//    /// Safe to delete, along with `TTSDiagnosticPanel.swift`, once
//    /// you've confirmed `generateSpeech` works end-to-end with cloning.
//    func diagnosticGenerateWithoutCloning(text: String) async throws -> URL {
//        try await loadModelIfNeeded()
//        guard let model else {
//            throw NSError(domain: "QwenTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model isn't loaded."])
//        }
//
//        let audio = try await model.generate(text: text, language: "english")
//
//        let outputURL = FileManager.default.temporaryDirectory
//            .appendingPathComponent("diagnostic-no-cloning-\(UUID().uuidString)")
//            .appendingPathExtension("wav")
//        try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
//        print("QwenTTSService: diagnostic file (no cloning) at \(outputURL.path)")
//        return outputURL
//    }
//}


//
//  QwenTTSServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

//import Foundation
//import Combine
//import MLX
//import Hub
//import Qwen3TTS
//
///// Fully on-device, no-API text-to-speech via Apple's MLX framework.
/////
///// Uses `AtomGradient/swift-qwen3-tts`, **not** `mlx-audio-swift`
///// (Blaizzy). Switched after isolating a real bug in the latter: its
///// generic `generate(text:voice:refAudio:refText:language:)` ignored
///// `text` entirely in voice-cloning mode (refAudio+refText given),
///// always speaking back `refText`'s content instead.
/////
///// `generateSpeech` now accepts `temperature` and `repetitionPenalty`
///// — the two sampling parameters `generateVoiceClone` actually exposes.
///// Callers set these from the voice profile's `applied*` fields so
///// Practice uses the same settings the user last generated with in
///// Voice Settings.
//final class QwenTTSService: ObservableObject {
//
//    enum State: Equatable {
//        case idle
//        case loadingModel
//        case ready
//        case generating
//        case failed(String)
//    }
//
//    @Published private(set) var state: State = .idle
//
//    private static let modelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
//
//    private var model: Qwen3TTSModel?
//
//    /// Loads the model if it hasn't been already. Safe to call before every
//    /// generation — it's a no-op once loaded.
//    func loadModelIfNeeded() async throws {
//        guard model == nil else { return }
//        state = .loadingModel
//        do {
//            let modelDir = try await Hub.snapshot(
//                from: Self.modelRepo,
//                progressHandler: { progress in
//                    print("QwenTTSService: downloading model — \(progress.completedUnitCount)/\(progress.totalUnitCount) files")
//                }
//            )
//            try Self.ensureTokenizerJSONExists(in: modelDir)
//            model = try await Qwen3TTSModel.fromPretrained(modelDir.path)
//            state = .ready
//        } catch {
//            state = .failed("Failed to load Qwen3-TTS model: \(error.localizedDescription)")
//            throw error
//        }
//    }
//
//    /// `swift-transformers` requires a local `tokenizer.json`,
//    /// but the Qwen3-TTS MLX repos only ship `vocab.json` + `merges.txt`.
//    /// Build the equivalent fast-tokenizer file in the downloaded cache so
//    /// `AutoTokenizer.from(modelFolder:)` can load the model.
//    private static func ensureTokenizerJSONExists(in modelDir: URL) throws {
//        let tokenizerURL = modelDir.appendingPathComponent("tokenizer.json")
//        if FileManager.default.fileExists(atPath: tokenizerURL.path) { return }
//
//        let vocabURL = modelDir.appendingPathComponent("vocab.json")
//        let mergesURL = modelDir.appendingPathComponent("merges.txt")
//        guard FileManager.default.fileExists(atPath: vocabURL.path),
//              FileManager.default.fileExists(atPath: mergesURL.path) else {
//            return
//        }
//
//        let vocabData = try Data(contentsOf: vocabURL)
//        guard let vocab = try JSONSerialization.jsonObject(with: vocabData) as? [String: Any] else {
//            throw NSError(
//                domain: "QwenTTSService",
//                code: -2,
//                userInfo: [NSLocalizedDescriptionKey: "Couldn't read Qwen tokenizer vocabulary."]
//            )
//        }
//
//        let mergesText = try String(contentsOf: mergesURL, encoding: .utf8)
//        let merges = mergesText
//            .components(separatedBy: .newlines)
//            .compactMap { line -> [String]? in
//                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
//                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
//                let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
//                return parts.count == 2 ? parts : nil
//            }
//
//        let tokenizerConfig = try loadTokenizerConfig(from: modelDir)
//        let addedTokens = makeAddedTokens(from: tokenizerConfig, vocab: vocab)
//
//        let tokenizerJSON: [String: Any] = [
//            "version": "1.0",
//            "truncation": NSNull(),
//            "padding": NSNull(),
//            "added_tokens": addedTokens,
//            "normalizer": NSNull(),
//            "pre_tokenizer": [
//                "type": "ByteLevel",
//                "add_prefix_space": false,
//                "trim_offsets": true,
//                "use_regex": true
//            ],
//            "post_processor": NSNull(),
//            "decoder": ["type": "ByteLevel"],
//            "model": [
//                "type": "BPE",
//                "dropout": NSNull(),
//                "unk_token": NSNull(),
//                "continuing_subword_prefix": "",
//                "end_of_word_suffix": "",
//                "fuse_unk": false,
//                "byte_fallback": false,
//                "vocab": vocab,
//                "merges": merges
//            ]
//        ]
//
//        let data = try JSONSerialization.data(withJSONObject: tokenizerJSON, options: [.prettyPrinted, .sortedKeys])
//        try data.write(to: tokenizerURL, options: .atomic)
//        print("QwenTTSService: created missing tokenizer.json from vocab.json + merges.txt")
//    }
//
//    private static func loadTokenizerConfig(from modelDir: URL) throws -> [String: Any] {
//        let configURL = modelDir.appendingPathComponent("tokenizer_config.json")
//        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
//        let data = try Data(contentsOf: configURL)
//        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
//    }
//
//    private static func makeAddedTokens(from tokenizerConfig: [String: Any], vocab: [String: Any]) -> [[String: Any]] {
//        if let decoder = tokenizerConfig["added_tokens_decoder"] as? [String: Any] {
//            return decoder.compactMap { key, value -> [String: Any]? in
//                guard let id = Int(key), var token = value as? [String: Any] else { return nil }
//                token["id"] = id
//                return token
//            }
//            .sorted { lhs, rhs in
//                (lhs["id"] as? Int ?? 0) < (rhs["id"] as? Int ?? 0)
//            }
//        }
//
//        return vocab.compactMap { token, idValue -> [String: Any]? in
//            guard token.hasPrefix("<|"), token.hasSuffix("|>"), let id = numericID(from: idValue) else { return nil }
//            return [
//                "id": id,
//                "content": token,
//                "single_word": false,
//                "lstrip": false,
//                "rstrip": false,
//                "normalized": false,
//                "special": true
//            ]
//        }
//        .sorted { lhs, rhs in
//            (lhs["id"] as? Int ?? 0) < (rhs["id"] as? Int ?? 0)
//        }
//    }
//
//    private static func numericID(from value: Any) -> Int? {
//        if let intValue = value as? Int { return intValue }
//        if let number = value as? NSNumber { return number.intValue }
//        return nil
//    }
//
//    /// Generates speech for `text`, cloned to sound like the voice in
//    /// `referenceAudioURL`. `temperature` and `repetitionPenalty` come
//    /// from the voice profile's `applied*` fields — so Practice always
//    /// uses the same settings the user last saved via "Generate Voice".
//    ///
//    /// Default values match `generateVoiceClone`'s own defaults so
//    /// callers that don't specify them get sensible behaviour.
//    func generateSpeech(
//        text: String,
//        referenceAudioURL: URL,
//        referenceTranscript: String,
//        temperature: Float = 0.9,
//        repetitionPenalty: Float = 1.5
//    ) async throws -> URL {
//        try await loadModelIfNeeded()
//
//        guard let model else {
//            let error = NSError(
//                domain: "QwenTTSService",
//                code: -1,
//                userInfo: [NSLocalizedDescriptionKey: "Model isn't loaded."]
//            )
//            state = .failed(error.localizedDescription)
//            throw error
//        }
//
//        state = .generating
//        do {
//            let (_, refAudio) = try loadAudioArray(from: referenceAudioURL)
//
//            // `generateVoiceClone` is synchronous and CPU/GPU-heavy —
//            // detach so we don't block the calling actor (usually MainActor).
//            let audio = try await Task.detached(priority: .userInitiated) {
//                try model.generateVoiceClone(
//                    text: text,
//                    referenceAudio: refAudio,
//                    referenceText: referenceTranscript,
//                    language: "english",
//                    temperature: temperature,
//                    repetitionPenalty: repetitionPenalty
//                )
//            }.value
//
//            let outputURL = FileManager.default.temporaryDirectory
//                .appendingPathComponent(UUID().uuidString)
//                .appendingPathExtension("wav")
//            try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
//
//            state = .ready
//            return outputURL
//        } catch {
//            state = .failed("Speech generation failed: \(error.localizedDescription)")
//            throw error
//        }
//    }
//
//    /// TEMPORARY DIAGNOSTIC — plain (non-cloning) generation to sanity-check
//    /// `text:` handling in isolation. Safe to delete along with
//    /// `TTSDiagnosticPanel.swift` once the full flow is confirmed working.
//    func diagnosticGenerateWithoutCloning(text: String) async throws -> URL {
//        try await loadModelIfNeeded()
//        guard let model else {
//            throw NSError(domain: "QwenTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model isn't loaded."])
//        }
//
//        let audio = try await model.generate(text: text, language: "english")
//
//        let outputURL = FileManager.default.temporaryDirectory
//            .appendingPathComponent("diagnostic-no-cloning-\(UUID().uuidString)")
//            .appendingPathExtension("wav")
//        try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
//        print("QwenTTSService: diagnostic file (no cloning) at \(outputURL.path)")
//        return outputURL
//    }
//}


//
//  QwenTTSServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import Foundation
import Combine
import MLX
import Accelerate
import Hub
import Qwen3TTS

/// Fully on-device, no-API text-to-speech via Apple's MLX framework.
///
/// Uses `AtomGradient/swift-qwen3-tts`, **not** `mlx-audio-swift` (Blaizzy).
///
/// Two fixes applied here vs earlier versions:
///
/// 1. `language: "auto"` instead of `"english"` — "english" switches to
///    "think mode" (codec prefix [think, think_bos, 2050, think_eos]), which
///    was mispronouncing common words like "hi" as "he". "auto" uses
///    "nothink mode" ([nothink, think_bos, think_eos]) and auto-detects the
///    language from the text, matching the Python notebook's default.
///
/// 2. Peak normalization after generation — the codec decoder can produce
///    sample values slightly above 1.0. Audio hardware clamps output to
///    [-1, 1] at the DAC, so any value above 1.0 gets hard-clipped, causing
///    "pecah"/crackling. Peak-normalizing to 0.95 removes all clipping.
final class QwenTTSService: ObservableObject {

    enum State: Equatable {
        case idle
        case loadingModel
        case ready
        case generating
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private static let modelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"

    private var model: Qwen3TTSModel?

    func loadModelIfNeeded() async throws {
        guard model == nil else { return }
        state = .loadingModel
        do {
            let modelDir = try await Hub.snapshot(
                from: Self.modelRepo,
                progressHandler: { progress in
                    print("QwenTTSService: downloading model — \(progress.completedUnitCount)/\(progress.totalUnitCount) files")
                }
            )
            try Self.ensureTokenizerJSONExists(in: modelDir)
            model = try await Qwen3TTSModel.fromPretrained(modelDir.path)
            state = .ready
        } catch {
            state = .failed("Failed to load Qwen3-TTS model: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Public API

    func generateSpeech(
        text: String,
        referenceAudioURL: URL,
        referenceTranscript: String,
        temperature: Float = 0.9,
        repetitionPenalty: Float = 1.5
    ) async throws -> URL {
        try await loadModelIfNeeded()

        guard let model else {
            let error = NSError(
                domain: "QwenTTSService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model isn't loaded."]
            )
            state = .failed(error.localizedDescription)
            throw error
        }

        state = .generating
        do {
            let (_, refAudio) = try loadAudioArray(from: referenceAudioURL)

            // Normalize text before synthesis.
            // Qwen3-TTS-12Hz-1.7B-Base has known G2P issues with short
            // English words that are phonetically ambiguous — "hi" gets
            // pronounced /hi/ (like Spanish) instead of /haɪ/ (English).
            // This is a confirmed bug in the model (HuggingFace issue #7).
            // Workaround: replace known problematic words with spellings
            // that the model's internal G2P handles correctly.
            let normalizedText = Self.normalizeText(text)
            let normalizedTranscript = Self.normalizeText(referenceTranscript)

            let rawAudio = try await Task.detached(priority: .userInitiated) {
                try model.generateVoiceClone(
                    text: normalizedText,
                    referenceAudio: refAudio,
                    referenceText: normalizedTranscript,
                    language: "auto",
                    temperature: temperature,
                    repetitionPenalty: repetitionPenalty
                )
            }.value

            // Fix 2: peak-normalize before saving.
            // Codec decoder output can exceed [-1, 1], causing hard-clipping
            // ("pecah") at the DAC. Scale the whole waveform so the loudest
            // peak sits at 0.95, which removes all clipping while keeping
            // the same relative dynamics.
            let audio = Self.peakNormalize(rawAudio, targetPeak: 0.95)

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("wav")
            try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)

            state = .ready
            return outputURL
        } catch {
            state = .failed("Speech generation failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// TEMPORARY DIAGNOSTIC — safe to delete with TTSDiagnosticPanel.swift.
    func diagnosticGenerateWithoutCloning(text: String) async throws -> URL {
        try await loadModelIfNeeded()
        guard let model else {
            throw NSError(domain: "QwenTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model isn't loaded."])
        }

        let rawAudio = try await model.generate(text: text, language: "auto")
        let audio = Self.peakNormalize(rawAudio, targetPeak: 0.95)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostic-no-cloning-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
        print("QwenTTSService: diagnostic file (no cloning) at \(outputURL.path)")
        return outputURL
    }

    // MARK: - Audio normalization

    /// Scales `audio` so its loudest sample sits at exactly `targetPeak`.
    /// If the current peak is already at or below `targetPeak`, returns
    /// the array unchanged (no unnecessary up-gain).
    private static func peakNormalize(_ audio: MLXArray, targetPeak: Float) -> MLXArray {
        let samples = audio.asArray(Float.self)
        guard !samples.isEmpty else { return audio }

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        guard peak > 1e-8 else { return audio }   // silence — nothing to scale
        guard peak > targetPeak else { return audio } // already within range

        return audio * MLXArray(targetPeak / peak)
    }

    // MARK: - Text normalization

    /// Rewrites words that Qwen3-TTS-12Hz-1.7B-Base is known to mispronounce
    /// (confirmed bug in the model's G2P/frontend, HuggingFace discussion #7).
    /// Uses whole-word regex replacement so "this" isn't mangled by the "hi"
    /// rule, "byte" isn't mangled by the "bye" rule, etc.
    private static func normalizeText(_ text: String) -> String {
        let rules: [(pattern: String, replacement: String)] = [
            // "hi" pronounced /hi/ (like Spanish) instead of /haɪ/ (English)
            (#"\bhi\b"#,  "hai"),
            (#"\bHi\b"#,  "Hai"),
            (#"\bHI\b"#,  "HAI"),
            // "bye" sometimes pronounced /bɪ/ instead of /baɪ/
            (#"\bbye\b"#, "bai"),
            (#"\bBye\b"#, "Bai"),
            (#"\bBYE\b"#, "BAI"),
        ]
        var result = text
        for rule in rules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: rule.replacement
                )
            }
        }
        return result
    }

    // MARK: - tokenizer.json bootstrap

    private static func ensureTokenizerJSONExists(in modelDir: URL) throws {
        let tokenizerURL = modelDir.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: tokenizerURL.path) { return }

        let vocabURL  = modelDir.appendingPathComponent("vocab.json")
        let mergesURL = modelDir.appendingPathComponent("merges.txt")
        guard FileManager.default.fileExists(atPath: vocabURL.path),
              FileManager.default.fileExists(atPath: mergesURL.path) else { return }

        let vocabData = try Data(contentsOf: vocabURL)
        guard let vocab = try JSONSerialization.jsonObject(with: vocabData) as? [String: Any] else {
            throw NSError(domain: "QwenTTSService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't read Qwen tokenizer vocabulary."])
        }

        let mergesText = try String(contentsOf: mergesURL, encoding: .utf8)
        let merges = mergesText
            .components(separatedBy: .newlines)
            .compactMap { line -> [String]? in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
                let parts = t.split(separator: " ", maxSplits: 1).map(String.init)
                return parts.count == 2 ? parts : nil
            }

        let tokenizerConfig = try loadTokenizerConfig(from: modelDir)
        let addedTokens    = makeAddedTokens(from: tokenizerConfig, vocab: vocab)

        let tokenizerJSON: [String: Any] = [
            "version": "1.0",
            "truncation": NSNull(),
            "padding": NSNull(),
            "added_tokens": addedTokens,
            "normalizer": NSNull(),
            // Qwen3 (tiktoken-family) pre-tokenizer: two-step Sequence.
            //
            // Step 1 — Split by regex: breaks raw text into word-level chunks
            // first, before byte-level encoding. Without this step, short
            // words like "hi" get merged with surrounding characters by BPE
            // and produce the wrong token → wrong pronunciation. This is the
            // exact regex Qwen2/Qwen3 tokenizers use (GPT-2 / tiktoken style).
            //
            // Step 2 — ByteLevel: encodes each chunk's bytes using the
            // printable-Unicode mapping, the same way it was done during
            // vocab training.
            //
            // Previous version only had Step 2 (ByteLevel alone, use_regex=true).
            // That approximates the split via ByteLevel's own regex, but the
            // output token IDs differ subtly from the original — enough to
            // mispronounce "hi" as "he".
            "pre_tokenizer": [
                "type": "Sequence",
                "pretokenizers": [
                    [
                        "type": "Split",
                        "pattern": [
                            "Regex": "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
                        ],
                        "behavior": "Isolated",
                        "invert": false
                    ],
                    [
                        "type": "ByteLevel",
                        "add_prefix_space": false,
                        "trim_offsets": true,
                        "use_regex": false
                    ]
                ]
            ] as [String: Any],
            "post_processor": NSNull(),
            "decoder": ["type": "ByteLevel"],
            "model": [
                "type": "BPE",
                "dropout": NSNull(),
                "unk_token": NSNull(),
                "continuing_subword_prefix": "",
                "end_of_word_suffix": "",
                "fuse_unk": false,
                "byte_fallback": false,
                "vocab": vocab,
                "merges": merges
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: tokenizerJSON, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: tokenizerURL, options: .atomic)
        print("QwenTTSService: created missing tokenizer.json from vocab.json + merges.txt")
    }

    private static func loadTokenizerConfig(from modelDir: URL) throws -> [String: Any] {
        let url = modelDir.appendingPathComponent("tokenizer_config.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func makeAddedTokens(from config: [String: Any], vocab: [String: Any]) -> [[String: Any]] {
        if let decoder = config["added_tokens_decoder"] as? [String: Any] {
            return decoder.compactMap { key, value -> [String: Any]? in
                guard let id = Int(key), var token = value as? [String: Any] else { return nil }
                token["id"] = id
                return token
            }
            .sorted { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
        }
        return vocab.compactMap { token, idValue -> [String: Any]? in
            guard token.hasPrefix("<|"), token.hasSuffix("|>"), let id = numericID(from: idValue) else { return nil }
            return ["id": id, "content": token, "single_word": false,
                    "lstrip": false, "rstrip": false, "normalized": false, "special": true]
        }
        .sorted { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
    }

    private static func numericID(from value: Any) -> Int? {
        if let i = value as? Int         { return i }
        if let n = value as? NSNumber    { return n.intValue }
        return nil
    }
}
