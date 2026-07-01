//
//  HistoryDetailView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

import SwiftUI

struct HistoryDetailView: View {
    let entry: PracticeHistoryEntry
    var onBack: () -> Void = {}

    @State private var showWordFeedback = true
    @StateObject private var recordingPlayer = AudioPlayerService()
    @StateObject private var correctedPlayer = AudioPlayerService()

    private var hasFeedback: Bool { !entry.feedbackItems.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                backButton
                header

                PlaybackTranscriptCard(
                    title: "Your Recording",
                    badgeText: entry.date,
                    words: entry.recordingWords,
                    mode: .original,
                    durationLabel: "—",
                    footnote: nil,
                    isPlaying: recordingPlayer.isPlaying,
                    onPlay: {
                        if let url = entry.recordingURL {
                            recordingPlayer.play(url: url)
                        }
                    }
                )

                PlaybackTranscriptCard(
                    title: "Corrected (Example with Your Voice)",
                    badgeText: "Generated",
                    words: entry.recordingWords,
                    mode: .corrected,
                    durationLabel: "—",
                    footnote: "This is how it should sound with your voice and correct pronunciation.",
                    trailingAccessory: hasFeedback ? {
                        AnyView(
                            Button(action: { withAnimation { showWordFeedback.toggle() } }) {
                                HStack(spacing: 4) {
                                    Text(showWordFeedback ? "Hide Details" : "Show Details")
                                    Image(systemName: showWordFeedback ? "chevron.up" : "chevron.down")
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        )
                    } : nil,
                    isPlaying: correctedPlayer.isPlaying,
                    onPlay: {
                        if let url = entry.correctedAudioURL {
                            correctedPlayer.play(url: url)
                        }
                    }
                )

                if hasFeedback && showWordFeedback {
                    WordFeedbackCarousel(items: entry.feedbackItems)
                }
            }
            .padding(24)
        }
        .background(AppTheme.pageBackground)
        .onDisappear {
            recordingPlayer.stop()
            correctedPlayer.stop()
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("History")
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.accent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.largeTitle.weight(.bold))
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption2)
                    Text(entry.date)
                    Text("•")
                    Image(systemName: "mic").font(.caption2)
                    Text(entry.voiceName)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            ScoreRingView(score: entry.score)
        }
    }
}

#Preview {
    HistoryDetailView(entry: [PracticeHistoryEntry].sampleHistory[0])
        .frame(width: 1000, height: 850)
}
