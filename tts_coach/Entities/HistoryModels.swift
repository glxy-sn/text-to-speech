//
//  HistoryModels.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

//
//  HistoryModels.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Data types for the History feature.
///
/// Revision: added `recordingURL` and `correctedAudioURL` to
/// `PracticeHistoryEntry`. These point to files in Application Support
/// (not the temp directory) — copied there by `PracticeViewModel`
/// when the session is saved, so they survive app restarts.

struct PracticeHistoryEntry: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let score: Int
    let textPreview: String
    let voiceName: String
    let recordingWords: [ScoredWord]
    let feedbackItems: [WordFeedbackItem]

    /// Permanent URL of the user's recorded voice — nil for entries
    /// saved before audio persistence was added, or if recording failed.
    var recordingURL: URL?

    /// Permanent URL of the TTS-corrected audio — nil for entries saved
    /// before audio persistence was added, or if generation failed.
    var correctedAudioURL: URL?
}

// MARK: - Sample data (previews / dev only)

extension Array where Element == PracticeHistoryEntry {
    static let sampleHistory: [PracticeHistoryEntry] = [
        PracticeHistoryEntry(
            title: "When the sunlight strikes raindrops…",
            date: "Today, 14:20",
            score: 82,
            textPreview: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow.",
            voiceName: "My Voice",
            recordingWords: .sampleRecordingWords,
            feedbackItems: .sampleFeedback,
            recordingURL: nil,
            correctedAudioURL: nil
        ),
        PracticeHistoryEntry(
            title: "The rainbow is a division of white…",
            date: "Yesterday, 09:05",
            score: 91,
            textPreview: "The rainbow is a division of white light into many beautiful colors.",
            voiceName: "My Voice",
            recordingWords: .sampleRecordingWords,
            feedbackItems: [],
            recordingURL: nil,
            correctedAudioURL: nil
        ),
        PracticeHistoryEntry(
            title: "These take the shape of a long…",
            date: "3 days ago",
            score: 76,
            textPreview: "These take the shape of a long round arch, with its path high above.",
            voiceName: "My Voice",
            recordingWords: .sampleRecordingWords,
            feedbackItems: .sampleFeedback,
            recordingURL: nil,
            correctedAudioURL: nil
        )
    ]
}
