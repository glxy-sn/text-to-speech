//
//  VoiceSelection.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// "Voice Data" section — matches mockup image 7's bottom block.
/// `onDelete` only fires after the user confirms in the dialog below —
/// it used to fire immediately with no confirmation at all.
struct VoiceDataSection: View {
    let voice: VoiceProfile
    var onDelete: () -> Void = {}

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Data").font(.headline)

            HStack(spacing: 12) {
                statBox(icon: "waveform", label: "Recording Length", value: voice.recordingLength)
                statBox(icon: "doc", label: "Sample Size", value: voice.sampleSize)
                statBox(icon: "calendar", label: "Created", value: voice.createdDate)
            }

            HStack {
                Text("Your voice data is stored locally on this device and never shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete Voice...") {
                    isShowingDeleteConfirmation = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            "Delete \"\(voice.name)\"?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. The voice and its settings will be permanently removed.")
        }
    }

    private func statBox(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.callout.weight(.semibold))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

#Preview {
    VoiceDataSection(voice: VoiceProfile.preview)
        .padding()
        .frame(width: 600)
}
