//
//  ResultsModels.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//


import SwiftUI

/// Lightweight, UI-only data types for the Results screen.

enum PronunciationStatus {
    case good
    case needsWork
    case incorrect

    var color: Color {
        switch self {
        case .good:      return .green
        case .needsWork: return .orange
        case .incorrect: return .red
        }
    }
}

struct ScoredWord: Identifiable {
    let id = UUID()
    let text: String
    let status: PronunciationStatus
}

extension Array where Element == ScoredWord {
    /// Builds a word list from real practice text with every word marked `.good` —
    /// used as a safe fallback when no real scoring data is available.
    static func allGood(from text: String) -> [ScoredWord] {
        text.split(separator: " ").map { ScoredWord(text: String($0), status: .good) }
    }
}

enum WordFeedbackContent {
    case needsReview(score: Int, youSaidIPA: String, expectedIPA: String, tip: String)
    case good
}

struct WordFeedbackItem: Identifiable {
    let id = UUID()
    let word: String
    let status: PronunciationStatus
    let content: WordFeedbackContent
}

// MARK: - ScoringResult

/// The fully-mapped output of one `PronunciationScoringService.score()` call.
/// Carries everything the results screen and history need to render real data.
struct ScoringResult {
    let overallScore: Int              // 0 – 100 (average GOP × 100)
    let scoredWords: [ScoredWord]      // word-level coloured chips
    let feedbackItems: [WordFeedbackItem]  // phoneme-level carousel cards

    /// Safe fallback when scoring isn't available (model missing, audio error, etc.).
    /// Produces a result that looks like the old placeholder behaviour so the
    /// rest of the flow is unaffected.
    static func placeholder(for text: String) -> ScoringResult {
        ScoringResult(
            overallScore: 0,
            scoredWords: .allGood(from: text),
            feedbackItems: []
        )
    }
}

// MARK: - Sample data (previews / dev only)

extension Array where Element == ScoredWord {
    static let sampleRecordingWords: [ScoredWord] = [
        .init(text: "Lorem",       status: .good),
        .init(text: "ipsum",       status: .good),
        .init(text: "dolor",       status: .good),
        .init(text: "sit",         status: .good),
        .init(text: "amet",        status: .good),
        .init(text: "consectetur", status: .incorrect),
        .init(text: "adipiscing",  status: .needsWork),
        .init(text: "elit",        status: .good),
        .init(text: "sed",         status: .good),
        .init(text: "do",          status: .good),
        .init(text: "eiusmod",     status: .incorrect),
        .init(text: "tempor",      status: .good),
        .init(text: "incididunt",  status: .needsWork),
        .init(text: "ut",          status: .good),
        .init(text: "labore",      status: .good),
        .init(text: "et.",         status: .good)
    ]
}

extension Array where Element == WordFeedbackItem {
    static let sampleFeedback: [WordFeedbackItem] = [
        .init(word: "consecttur", status: .incorrect, content: .needsReview(
            score: 45,
            youSaidIPA: "/kənˈsɛktətər/",
            expectedIPA: "/kənˌsɛkˈtɛtʊr/",
            tip: "Try to reduce the \"t\" in the middle and stress the second syllable."
        )),
        .init(word: "adipiscing", status: .needsWork, content: .needsReview(
            score: 65,
            youSaidIPA: "/əˌdɪpɪsɪŋ/",
            expectedIPA: "/əˈdɪpɪsɪŋ/",
            tip: "The first syllable should be a schwa /ə/. Try to relax your mouth."
        )),
        .init(word: "eiusmod", status: .incorrect, content: .needsReview(
            score: 40,
            youSaidIPA: "/eɪˈjusmɒd/",
            expectedIPA: "/iːˈjusmɒd/",
            tip: "The first sound is long 'ee' /iː/, not 'ay'."
        )),
        .init(word: "incididunt", status: .needsWork, content: .needsReview(
            score: 70,
            youSaidIPA: "/ɪnˈsɪdɪdənt/",
            expectedIPA: "/ɪnˈsɪdɪdʊnt/",
            tip: "Stress the second syllable 'di' more clearly."
        )),
        .init(word: "ut", status: .good, content: .good)
    ]
}
