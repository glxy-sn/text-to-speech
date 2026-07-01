//
//  VoiceRefProcessingStepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import SwiftUI

/// Brief step shown between "Recording" and "Review" while
/// `AudioPreprocessingService` runs (silence trim, denoise, resample,
/// loudness normalize) on the freshly-recorded clip. Purely a loading
/// state — same idea as `PracticeGeneratingStepView`, just much shorter
/// since this is local DSP, not an LLM/TTS call.
struct VoiceRefProcessingStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Processing your recording...")
                .font(.callout.weight(.medium))
            Text("Trimming silence, reducing noise, and normalizing volume.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

#Preview {
    VoiceRefProcessingStepView()
        .frame(width: 420, height: 300)
}
