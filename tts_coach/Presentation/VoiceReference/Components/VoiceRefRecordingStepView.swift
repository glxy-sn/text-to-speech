//
//  VoiceRefRecordingStepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import Foundation

/// Step 2 of 3 — live "Recording..." state with a counting timer.
/// The timer is derived from `startedAt` via `TimelineView` rather than a
/// stored counter, so there's no risk of it drifting or resetting if the
/// view gets re-evaluated.
///
/// `isCapturingAudio` reflects whether the underlying `AudioRecorderService`
/// is genuinely capturing right now — separate from this countdown, which
/// is purely cosmetic UI state. If they disagree (timer running but no
/// real capture, e.g. mic permission denied), a warning banner shows
/// instead of silently producing an empty recording.
struct VoiceRefRecordingStepView: View {
    let script: String
    let startedAt: Date
    var isCapturingAudio: Bool = true
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Please read aloud")
                .font(.title3.weight(.semibold))

            ScriptTextBox(text: script)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Recording...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text(timeString(elapsed))
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
            }

            AnimatedWaveformView()

            if !isCapturingAudio {
                capturingWarningBanner
            }

            Button(action: onStop) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var capturingWarningBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Microphone isn't capturing audio. Check mic permission in System Settings, then try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    VoiceRefRecordingStepView(
        script: "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et.",
        startedAt: Date(),
        onStop: {}
    )
    .padding(28)
    .frame(width: 420)
}
