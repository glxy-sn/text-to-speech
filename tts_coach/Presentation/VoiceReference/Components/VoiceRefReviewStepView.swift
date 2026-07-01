//
//  VoiceRefReviewStepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import Foundation

/// Step 3 of 3 — review the recording before confirming.
/// `isPlaying`/`onPlay` now wire to a real `AudioPlayerService` via the
/// parent View's ViewModel — this view itself stays simple and doesn't
/// know that, it just renders whatever playback state it's given.
struct VoiceRefReviewStepView: View {
    let script: String
    let durationSeconds: Int
    var isPlaying: Bool = false
    var onPlay: () -> Void = {}
    var onReRecord: () -> Void
    var onNext: () -> Void

    private var durationLabel: String {
        String(format: "0:00 / %d:%02d", durationSeconds / 60, durationSeconds % 60)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Nice! Let's review your recording.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            ScriptTextBox(text: script)

            HStack(spacing: 12) {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                AnimatedWaveformView(isAnimating: isPlaying)

                Text(durationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            HStack(spacing: 12) {
                Button("Re-record", action: onReRecord)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    VoiceRefReviewStepView(
        script: "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et.",
        durationSeconds: 12,
        onReRecord: {},
        onNext: {}
    )
    .padding(28)
    .frame(width: 420)
}
