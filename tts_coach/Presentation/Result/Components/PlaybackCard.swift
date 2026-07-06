//
//  PlaybackCard.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Shared card layout used for both "Your Recording" and
/// "Corrected (Example with Your Voice)" sections in mockup image 6.
/// `isPlaying`/`onPlay` default to inert values so existing call sites
/// (e.g. `HistoryDetailView`, which has no real audio file per entry yet)
/// keep compiling unchanged; callers with a real file (currently
/// `PracticeResultsView`) wire these to an `AudioPlayerService`.
struct PlaybackTranscriptCard: View {
    let title: String
    let badgeText: String
    let words: [ScoredWord]
    let mode: WordDisplayMode
    let durationLabel: String
    let footnote: String?
    var trailingAccessory: (() -> AnyView)? = nil
    var levels: [Float] = Array(repeating: 0.1, count: 60)
    var isPlaying: Bool = false
    var onPlay: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(title).font(.headline)

                Text(badgeText)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())

                Spacer()

                Text(durationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let trailingAccessory {
                    trailingAccessory()
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                WordFlowText(words: words, mode: mode)
            }

            if isPlaying {
                WaveformView(levels: levels)
            } else {
                Spacer()
            }

            if let footnote {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(footnote)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

#Preview {
    PlaybackTranscriptCard(
        title: "Your Recording",
        badgeText: "Just now",
        words: .sampleRecordingWords,
        mode: .original,
        durationLabel: "0:12",
        footnote: nil
    )
    .padding()
    .frame(width: 700)
}
