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

        // Step 1: Preprocess baseline audio
        let processedTTSURL = try await AudioRecordingService.trimSilenceAndDenoise(audioURL: ttsAudioURL)
        let normalizedTTSURL = try await AudioRecordingService.normalizeTempo(audioURL: processedTTSURL, targetScript: practiceText, targetWPM: 130.0)

        // Step 2: Extract baseline target phonemes
        let ttsBuffer = try AudioService.loadAudio(from: normalizedTTSURL)
        let phonemesWithFrames = try engine.extractTargetPhonemes(from: ttsBuffer)
        let targetPhonemesList = phonemesWithFrames.map { $0.symbol }
        guard !targetPhonemesList.isEmpty else { return .placeholder(for: practiceText) }

        // Determine ASR Locale based on script contents
        let asrLocale = practiceText.range(of: "\\p{Han}", options: .regularExpression) != nil ? "zh-CN" : "en-US"

        // Step 3: ASR Word Timings
        let asrTimings: [SpeechAlignmentService.WordTiming]
        do {
            asrTimings = try await SpeechAlignmentService.getWordTimings(audioURL: normalizedTTSURL, localeIdentifier: asrLocale)
        } catch {
            print("ASR failed: \(error), falling back")
            asrTimings = []
        }
        let baselineASRTimings = SpeechAlignmentService.alignTimingsToTarget(targetScript: practiceText, asrTimings: asrTimings)

        // Step 4: Canonical Alignment
        let targetWordAlignments = PhonemeWordAligner.alignHybrid(targetScript: practiceText, asrTimings: baselineASRTimings, phonemes: phonemesWithFrames)

        // Step 5: Preprocess User Audio
        let normalizedUserURL = try await AudioRecordingService.normalizeTempo(audioURL: userRecordingURL, targetScript: practiceText, targetWPM: 125.0)

        // Step 6: Extract User Logits
        let userBuffer = try AudioService.loadAudio(from: normalizedUserURL)
        let userLogits = try engine.extractUserLogits(from: userBuffer)
        let greedyResult = engine.runGreedyDecodeWithFrames(logits: userLogits)

        // Step 7: Score Pronunciation
        let phoneScores = scorer.scorePronunciation(
            userLogits: userLogits,
            targetPhonemes: targetPhonemesList,
            vocabulary: engine.vocabulary,
            greedyAnchors: greedyResult
        )

        // Step 8: Extract ORIGINAL Audio Word Timings for UI Playback
        let originalUserTimings = (try? await SpeechAlignmentService.getWordTimings(audioURL: userRecordingURL, localeIdentifier: asrLocale)) ?? []
        let originalUserAligned = SpeechAlignmentService.alignTimingsToTarget(targetScript: practiceText, asrTimings: originalUserTimings)

        let originalTTSTimings = (try? await SpeechAlignmentService.getWordTimings(audioURL: ttsAudioURL, localeIdentifier: asrLocale)) ?? []
        let originalTTSAligned = SpeechAlignmentService.alignTimingsToTarget(targetScript: practiceText, asrTimings: originalTTSTimings)

        // Step 9: Map to UI models using our canonical alignments
        var scoredWordsList = [ScoredWord]()
        var allWordScores = [Float]()
        var feedbackItems = [WordFeedbackItem]()

        for (i, alignment) in targetWordAlignments.enumerated() {
            let scoresForWord = alignment.phonemeIndices.compactMap { idx in idx < phoneScores.count ? phoneScores[idx] : nil }
            let avg = scoresForWord.isEmpty ? 0.0 : scoresForWord.map { $0.gopScore }.reduce(0, +) / Float(scoresForWord.count)
            allWordScores.append(avg)

            let status: PronunciationStatus = scoresForWord.isEmpty ? .good : (avg > 0.7 ? .good : avg > 0.4 ? .needsWork : .incorrect)
            scoredWordsList.append(ScoredWord(text: alignment.word, status: status))
            
            // Only add feedback items if we have phoneme scores
            if !scoresForWord.isEmpty {
                let phonemeFeedbacks = scoresForWord.map { phone in
                    PhonemeFeedback(symbol: phone.symbol, score: Int(phone.gopScore * 100))
                }
                
                let userTiming = i < originalUserAligned.count ? originalUserAligned[i] : nil
                let ttsTiming = i < originalTTSAligned.count ? originalTTSAligned[i] : nil
                
                feedbackItems.append(WordFeedbackItem(
                    word: alignment.word,
                    status: status,
                    overallScore: Int(avg * 100),
                    phonemes: phonemeFeedbacks,
                    startTime: userTiming?.startTime,
                    endTime: userTiming?.endTime,
                    ttsStartTime: ttsTiming?.startTime,
                    ttsEndTime: ttsTiming?.endTime
                ))
            }
        }

        let overallScore = allWordScores.isEmpty ? 0 : Int(min(100, max(0, (allWordScores.reduce(0, +) / Float(allWordScores.count)) * 100)))

        return ScoringResult(
            overallScore:  overallScore,
            scoredWords:   scoredWordsList,
            feedbackItems: feedbackItems
        )
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


}
