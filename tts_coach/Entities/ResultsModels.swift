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

struct PhonemeFeedback: Identifiable {
    let id = UUID()
    let symbol: String
    let score: Int
    
    var status: PronunciationStatus {
        score > 70 ? .good : score > 40 ? .needsWork : .incorrect
    }
}

struct WordFeedbackItem: Identifiable {
    let id = UUID()
    let word: String
    let status: PronunciationStatus
    let overallScore: Int
    let phonemes: [PhonemeFeedback]
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let ttsStartTime: TimeInterval?
    let ttsEndTime: TimeInterval?
}

// MARK: - ScoringResult

/// The fully-mapped output of one `PronunciationScoringService.score()` call.
/// Carries everything the results screen and history need to render real data.
struct ScoringResult {
    let overallScore: Int              // 0 – 100 (average GOP × 100)
    let scoredWords: [ScoredWord]      // word-level coloured chips
    let feedbackItems: [WordFeedbackItem]  // word-level carousel cards with phonemes

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
        .init(word: "consectetur", status: .incorrect, overallScore: 45, phonemes: [
            .init(symbol: "k", score: 80),
            .init(symbol: "ə", score: 75),
            .init(symbol: "n", score: 85),
            .init(symbol: "s", score: 30),
            .init(symbol: "ɛ", score: 40),
            .init(symbol: "k", score: 50),
            .init(symbol: "t", score: 20),
            .init(symbol: "ə", score: 45),
            .init(symbol: "t", score: 30),
            .init(symbol: "ʊ", score: 80),
            .init(symbol: "r", score: 85)
        ], startTime: 0.5, endTime: 1.2, ttsStartTime: 0.5, ttsEndTime: 1.2),
        .init(word: "adipiscing", status: .needsWork, overallScore: 65, phonemes: [
            .init(symbol: "ə", score: 55),
            .init(symbol: "d", score: 65),
            .init(symbol: "ɪ", score: 70),
            .init(symbol: "p", score: 80),
            .init(symbol: "ɪ", score: 45),
            .init(symbol: "s", score: 85),
            .init(symbol: "ɪ", score: 60),
            .init(symbol: "ŋ", score: 75)
        ], startTime: 1.3, endTime: 2.0, ttsStartTime: 1.3, ttsEndTime: 2.0),
        .init(word: "eiusmod", status: .incorrect, overallScore: 40, phonemes: [
            .init(symbol: "i", score: 30),
            .init(symbol: "j", score: 40),
            .init(symbol: "u", score: 50),
            .init(symbol: "s", score: 25),
            .init(symbol: "m", score: 80),
            .init(symbol: "ɒ", score: 75),
            .init(symbol: "d", score: 85)
        ], startTime: 2.1, endTime: 2.8, ttsStartTime: 2.1, ttsEndTime: 2.8)
    ]
}
