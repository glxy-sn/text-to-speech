//
//  RecordingReview.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Sits between "Record" and "Generate" — matches mockup image 4.
/// Playback button is a no-op for now (real audio Service comes later).
struct PracticeRecordingReviewStepView: View {
    let durationSeconds: Int
    var onGenerateCorrection: () -> Void
    var onReRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Recording").font(.headline)
                Text("Listen to your recording before generating a correction.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            playbackRow

            VStack(spacing: 6) {
                Button(action: onGenerateCorrection) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate Correction")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.large)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("The correction will be generated using this voice.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            tipBar
        }
    }

    private var playbackRow: some View {
        HStack(spacing: 12) {
            Button(action: { /* TODO: wire to real playback once audio Service exists */ }) {
                Image(systemName: "play.fill")
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            AnimatedWaveformView(barCount: 40, isAnimating: false)

            Text("00:00 / \(timeString(durationSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var tipBar: some View {
        HStack {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                Text("Tip: If something doesn't sound right, you can re-record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-record", action: onReRecord)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    PracticeRecordingReviewStepView(durationSeconds: 18, onGenerateCorrection: {}, onReRecord: {})
        .padding(24)
        .frame(width: 480)
}
