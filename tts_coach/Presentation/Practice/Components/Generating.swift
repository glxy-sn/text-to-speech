//
//  Generating.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import Foundation

/// Loading state — matches mockup image 5, plus a small read-only voice
/// indicator at the top.
///
/// Revision: voice picking used to live here as a popover, but cramming
/// "make a decision" and "watch a loading animation" into the same brief
/// moment was bad UX — too rushed. Picking now happens in its own step
/// (`PracticeVoiceSelectionStepView`) *before* this screen, so by the time
/// we're here the choice is already locked in — this just displays it.
///
/// Per a later revision: this now backs a real `QwenTTSService` call,
/// which can take a while on the very first run (downloading the model
/// from Hugging Face, multi-GB). `statusText` lets the caller override
/// the default copy to make that wait less confusing.
struct PracticeGeneratingStepView: View {
    let selectedVoiceName: String
    var statusText: String = "This usually takes a few seconds."

    var body: some View {
        VStack(spacing: 16) {
            voiceIndicatorChip

            Text("Generating Correction...")
                .font(.title3.weight(.semibold))

            Text("We're analyzing your pronunciation and creating a correction example using your own voice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            pulsingIcon
                .padding(.vertical, 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var voiceIndicatorChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.caption2)
            Text("Using: \(selectedVoiceName)")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.accentSoft)
        .clipShape(Capsule())
    }

    private var pulsingIcon: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let scale = 1.0 + 0.06 * sin(t * 3)
            ZStack {
                Circle()
                    .strokeBorder(AppTheme.accentSoft, lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 64, height: 64)
                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.accent)
            }
            .scaleEffect(scale)
        }
    }
}

#Preview {
    PracticeGeneratingStepView(selectedVoiceName: "Tiara")
        .frame(width: 480, height: 320)
}
