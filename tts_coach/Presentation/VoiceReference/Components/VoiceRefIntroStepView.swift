//
//  VoiceRefIntroStepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Step 1 of 3 — matches mockup image 8 ("Please read aloud" intro).
///
/// Revision: added `onUploadAudio` callback and "Upload Audio File"
/// button as an alternative to recording live.
struct VoiceRefIntroStepView: View {
    var onUploadAudio: () -> Void = {}
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 72, height: 72)
                Image(systemName: "mic.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 6) {
                Text("New Voice")
                    .font(.title3.weight(.semibold))
                Text("Read the upcoming paragraph with your natural voice.\n Maintain a relaxed pace and give ample room in between each word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Primary CTA — record live
            Button(action: onStart) {
                Text("Start Recording")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)

            // "or" separator
            HStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
            }

            // Secondary CTA — upload existing audio
            Button(action: onUploadAudio) {
                Label("Upload Audio File", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Supported: WAV, MP3, M4A, AIFF")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VoiceRefIntroStepView(
        onStart: {}
    )
    .padding(28)
    .frame(width: 420)
}
