//
//  PronunciationScoringService.swift
//  tts_coach
//
//  Created by Shafa Tiara on 01/07/26.
//

import Foundation
import CoreML
import AVFoundation
import Accelerate
import Combine

// MARK: - Errors

enum PronunciationScoringError: LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case audioLoadFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:  return "Wav2Vec2Phonetic.mlmodelc not found in bundle. Add the file to the Xcode target."
        case .modelNotLoaded: return "Pronunciation model is not loaded."
        case .audioLoadFailed: return "Could not load audio for pronunciation scoring."
        }
    }
}

// MARK: - Service

final class PronunciationScoringService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isReady   = false

    private var engine: AudioInferenceEngine?
    private let scorer = AlignmentScorerEngine()

    // MARK: - Public API

    /// Lazily loads the Wav2Vec2 CoreML model from the app bundle.
    /// Safe to call multiple times — no-op once loaded.
    func loadEngineIfNeeded() async throws {
        guard engine == nil else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        guard let modelURL = Bundle.main.url(forResource: "Wav2Vec2Phonetic", withExtension: "mlmodelc") else {
            throw PronunciationScoringError.modelNotFound
        }
        let loaded = try await AudioInferenceEngine.load(modelURL: modelURL)
        self.engine = loaded
        await MainActor.run { self.isReady = true }
    }

    /// Full scoring pass for one practice session:
    ///  1. Load and resample both audio files to 16 kHz PCM (what Wav2Vec2 expects).
    ///  2. Extract target IPA phonemes from the TTS baseline audio.
    ///  3. Extract raw logit posteriors from the user's recording.
    ///  4. CTC Forward-Backward → per-phoneme GOP scores.
    ///  5. Map phoneme scores → ScoringResult (overall, word-level, feedback cards).
    func score(
        practiceText: String,
        userRecordingURL: URL,
        ttsAudioURL: URL
    ) async throws -> ScoringResult {
        try await loadEngineIfNeeded()
        guard let engine else { throw PronunciationScoringError.modelNotLoaded }

        // Step 1 & 2: target phonemes from TTS audio
        let ttsBuffer = try Self.loadAudioForWav2Vec2(from: ttsAudioURL)
        let targetPhonemes = try engine.extractTargetPhonemes(from: ttsBuffer)
        guard !targetPhonemes.isEmpty else { return .placeholder(for: practiceText) }

        // Step 1 & 3: user logits + greedy decode
        let userBuffer  = try Self.loadAudioForWav2Vec2(from: userRecordingURL)
        let userLogits  = try engine.extractUserLogits(from: userBuffer)
        let greedyResult = engine.runGreedyDecodeWithFrames(logits: userLogits)
        let userGreedy   = greedyResult.map { $0.symbol }

        // Step 4: CTC Forward-Backward GOP
        let phoneScores = scorer.scorePronunciation(
            userLogits: userLogits,
            targetPhonemes: targetPhonemes,
            vocabulary: engine.vocabulary,
            greedyAnchors: greedyResult
        )

        // Step 5: Map to UI models
        let overallScore  = Self.makeOverallScore(phoneScores)
        let scoredWords   = Self.makeScoredWords(practiceText: practiceText, phoneScores: phoneScores)
        let feedbackItems = Self.makeFeedbackItems(phoneScores: phoneScores, userGreedy: userGreedy)

        return ScoringResult(
            overallScore:  overallScore,
            scoredWords:   scoredWords,
            feedbackItems: feedbackItems
        )
    }

    // MARK: - Mapping helpers

    /// Overall score 0–100: average GOP × 100.
    private static func makeOverallScore(_ scores: [PhoneScore]) -> Int {
        guard !scores.isEmpty else { return 0 }
        let avg = scores.map(\.gopScore).reduce(0, +) / Float(scores.count)
        return Int(min(100, max(0, avg * 100)))
    }

    /// Map the flat phoneme sequence to words proportionally by character length.
    /// Each word's GOP score is the average of its assigned phonemes' scores.
    private static func makeScoredWords(practiceText: String, phoneScores: [PhoneScore]) -> [ScoredWord] {
        let words = practiceText.split(separator: " ").map(String.init)
        guard !words.isEmpty, !phoneScores.isEmpty else { return .allGood(from: practiceText) }

        let totalChars  = max(1, words.map(\.count).reduce(0, +))
        let totalPhones = phoneScores.count
        var result: [ScoredWord] = []
        var phoneOffset = 0

        for (idx, word) in words.enumerated() {
            let isLast = idx == words.count - 1
            let count: Int
            if isLast {
                count = totalPhones - phoneOffset
            } else {
                count = max(1, Int(round(Float(word.count) / Float(totalChars) * Float(totalPhones))))
            }

            let start = phoneOffset
            let end   = min(phoneOffset + count, totalPhones)
            let slice = Array(phoneScores[start..<end])

            let status: PronunciationStatus
            if slice.isEmpty {
                status = .good
            } else {
                let avg = slice.map(\.gopScore).reduce(0, +) / Float(slice.count)
                status = avg > 0.7 ? .good : avg > 0.4 ? .needsWork : .incorrect
            }

            result.append(ScoredWord(text: word, status: status))
            phoneOffset = end
        }

        return result
    }

    /// Phoneme-level feedback cards for the carousel.
    /// Good phonemes get a green "Great!" card; imperfect ones get a detail card
    /// showing score, expected IPA, an approximated "you said" IPA
    /// (via proportional mapping from the user's greedy decode), and a tip.
    private static func makeFeedbackItems(
        phoneScores: [PhoneScore],
        userGreedy: [String]
    ) -> [WordFeedbackItem] {
        let total     = max(1, phoneScores.count)
        let userCount = userGreedy.count

        return phoneScores.enumerated().map { (idx, phone) in
            let score  = phone.gopScore
            let status: PronunciationStatus = score > 0.7 ? .good : score > 0.4 ? .needsWork : .incorrect

            if status == .good {
                return WordFeedbackItem(word: phone.symbol, status: .good, content: .good)
            }

            // Proportional index into the user's greedy sequence
            let userIdx  = userCount > 0
                ? min(Int(Float(idx) / Float(total) * Float(userCount)), userCount - 1)
                : -1
            let youSaid  = userIdx >= 0 ? "/\(userGreedy[userIdx])/" : "—"

            return WordFeedbackItem(
                word: phone.symbol,
                status: status,
                content: .needsReview(
                    score: Int(score * 100),
                    youSaidIPA: youSaid,
                    expectedIPA: "/\(phone.symbol)/",
                    tip: tipForPhoneme(phone.symbol)
                )
            )
        }
    }

    /// Generic pronunciation tip based on phoneme class.
    private static func tipForPhoneme(_ symbol: String) -> String {
        let vowels: Set<String>     = ["ə","ɪ","ɛ","æ","ʌ","ɑ","ɔ","ʊ","u","i","e","o","a",
                                        "eɪ","aɪ","oʊ","aʊ","ɔɪ","ɜː","ɑː","ɔː","iː","uː","ɚ"]
        let fricatives: Set<String> = ["f","v","θ","ð","s","z","ʃ","ʒ","h"]
        let stops: Set<String>      = ["p","b","t","d","k","ɡ"]
        let nasals: Set<String>     = ["m","n","ŋ"]
        let approximants: Set<String> = ["ɹ","l","w","j"]

        if vowels.contains(symbol)     { return "Focus on your tongue height and lip shape for this vowel sound." }
        if fricatives.contains(symbol) { return "Keep a steady stream of air — don't stop or burst it." }
        if stops.contains(symbol)      { return "Build up air pressure fully, then release it cleanly." }
        if nasals.contains(symbol)     { return "Direct the airflow through your nose for this nasal consonant." }
        if approximants.contains(symbol) { return "Keep your tongue and lips relaxed while forming this sound." }
        return "Listen to the baseline carefully and try to match this sound precisely."
    }

    // MARK: - Audio loading (adapted from friend's AudioService.loadAudio)

    /// Load any audio file (WAV, M4A, etc.), resample to 16 kHz mono,
    /// and apply zero-mean / unit-variance normalization — the exact
    /// preprocessing `wav2vec2-xlsr-53-espeak-cv-ft` expects.
    private static func loadAudioForWav2Vec2(from url: URL) throws -> MLMultiArray {
        let file = try AVAudioFile(forReading: url)
        let srcFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            throw PronunciationScoringError.audioLoadFailed
        }
        try file.read(into: srcBuffer)

        // Target: 16 kHz mono float32
        let targetSampleRate: Double = 16_000
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        let finalBuffer: AVAudioPCMBuffer
        if srcFormat.sampleRate != targetSampleRate || srcFormat.channelCount != 1 {
            guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
                throw PronunciationScoringError.audioLoadFailed
            }
            let dstCapacity = AVAudioFrameCount(
                Double(srcBuffer.frameLength) * targetSampleRate / srcFormat.sampleRate
            ) + 1024
            guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: dstCapacity) else {
                throw PronunciationScoringError.audioLoadFailed
            }
            var inputConsumed = false
            var conversionError: NSError?
            converter.convert(to: dstBuffer, error: &conversionError) { _, outStatus in
                if inputConsumed { outStatus.pointee = .endOfStream; return nil }
                inputConsumed = true
                outStatus.pointee = .haveData
                return srcBuffer
            }
            if let conversionError { throw conversionError }
            finalBuffer = dstBuffer
        } else {
            finalBuffer = srcBuffer
        }

        let frameLength = Int(finalBuffer.frameLength)
        guard let channelData = finalBuffer.floatChannelData?[0] else {
            throw PronunciationScoringError.audioLoadFailed
        }

        let shape = [1, NSNumber(value: frameLength)]
        let multiArray = try MLMultiArray(shape: shape, dataType: .float32)
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(multiArray.dataPointer))

        // Zero-mean, unit-variance normalisation (what Wav2Vec2 expects)
        var mean: Float = 0.0
        var stdDev: Float = 0.0
        vDSP_normalize(channelData, 1, ptr, 1, &mean, &stdDev, vDSP_Length(frameLength))

        return multiArray
    }
}
