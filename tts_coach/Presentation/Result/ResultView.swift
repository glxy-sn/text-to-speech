//
//  ResultView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Full Results screen — matches mockup image 6.
///
/// Revision: now accepts real pronunciation scoring data from
/// `PronunciationScoringService` (via `PracticeViewModel`) and uses it for:
///  - `ResultsHeaderView` score ring (real overall GOP score, not hardcoded 82)
///  - `WordFlowText` word colouring (real per-word status)
///  - `WordFeedbackCarousel` (real per-phoneme cards, only shown when non-empty)
///
/// All params default to placeholder values so existing non-scoring code paths
/// (e.g. HistoryDetailView previews) still compile unchanged.
struct PracticeResultsView: View {
    @StateObject private var recordingPlayer = AudioPlayerService()
    @StateObject private var correctedPlayer = AudioPlayerService()

    let practiceText: String
    var recordingURL: URL?
    var correctedAudioURL: URL?
    var overallScore: Int = 0
    var scoredWords: [ScoredWord] = []
    var feedbackItems: [WordFeedbackItem] = []
    var onStartNewPractice: () -> Void = {}

    /// The words used in both transcript cards. Falls back to `allGood` if
    /// scoring hasn't run yet (e.g. model was missing from bundle).
    private var displayWords: [ScoredWord] {
        scoredWords.isEmpty ? .allGood(from: practiceText) : scoredWords
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                newPracticeButton

                ResultsHeaderView(
                    score: overallScore,
                    onDownload: downloadCorrectedAudio
                )

                PlaybackTranscriptCard(
                    title: "Your Recording",
                    badgeText: "Just now",
                    words: displayWords,
                    mode: .original,        // coloured chips where score < good
                    durationLabel: "0:12",
                    footnote: nil,
                    levels: recordingPlayer.currentLevels,
                    isPlaying: recordingPlayer.isPlaying,
                    onPlay: {
                        if let recordingURL { recordingPlayer.play(url: recordingURL) }
                    }
                )

                PlaybackTranscriptCard(
                    title: "Corrected (Example with Your Voice)",
                    badgeText: "Generated",
                    words: displayWords,
                    mode: .corrected,       // all words shown in green (this is the reference)
                    durationLabel: "0:12",
                    footnote: "This is how it should sound with your voice and correct pronunciation.",
                    levels: correctedPlayer.currentLevels,
                    isPlaying: correctedPlayer.isPlaying,
                    onPlay: {
                        if let correctedAudioURL { correctedPlayer.play(url: correctedAudioURL) }
                    }
                )

                // Word-level feedback with nested phonemes
                if !feedbackItems.isEmpty {
                    WordFeedbackCarousel(
                        items: feedbackItems,
                        onPlayUser: { wordItem in
                            guard let recordingURL,
                                  let start = wordItem.startTime,
                                  let end = wordItem.endTime else { return }
                            recordingPlayer.playSegment(url: recordingURL, startTime: start, endTime: end)
                        },
                        onPlayTTS: { wordItem in
                            guard let correctedAudioURL,
                                  let start = wordItem.ttsStartTime,
                                  let end = wordItem.ttsEndTime else { return }
                            correctedPlayer.playSegment(url: correctedAudioURL, startTime: start, endTime: end)
                        }
                    )
                }
            }
            .padding(24)
        }
        .background(AppTheme.pageBackground)
    }

    // MARK: - Sub-views

    private var newPracticeButton: some View {
        Button(action: onStartNewPractice) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                Text("New Practice")
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
    }

    // MARK: - Download

    /// Opens a native NSSavePanel and copies the corrected WAV to the user's
    /// chosen location. No-op if `correctedAudioURL` is nil.
    private func downloadCorrectedAudio() {
        guard let sourceURL = correctedAudioURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [UTType.wav]
        panel.nameFieldStringValue = "pronunciation_correction.wav"
        panel.message = "Save your corrected pronunciation audio"
        panel.prompt  = "Save"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                print("PracticeResultsView: failed to save audio — \(error)")
            }
        }
    }
}

#Preview {
    PracticeResultsView(
        practiceText: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
        overallScore: 74,
        scoredWords: .sampleRecordingWords,
        feedbackItems: .sampleFeedback
    )
    .frame(width: 1000, height: 850)
}
