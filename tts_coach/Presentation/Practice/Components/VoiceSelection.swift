//
//  VoiceSelection.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

import SwiftUI

/// New step inserted between "Record" and "Generate" per a revision:
/// picking the voice deserves its own deliberate moment, not a rushed
/// popover crammed into the Generating screen. Pulls from the shared
/// `VoiceLibraryStore` so it's the same voices/settings the Voices page
/// manages.
struct PracticeVoiceSelectionStepView: View {
    let voices: [VoiceProfile]
    @Binding var selectedVoiceID: VoiceProfile.ID?
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Voice").font(.headline)
                Text("Which voice should we use to generate the correction example?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(voices) { voice in
                    Button {
                        selectedVoiceID = voice.id
                    } label: {
                        voiceRow(voice)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onConfirm) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate Correction")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)
            .disabled(selectedVoiceID == nil)
        }
    }

    private func voiceRow(_ voice: VoiceProfile) -> some View {
        let isSelected = voice.id == selectedVoiceID
        return HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? AppTheme.accent : AppTheme.accentSoft)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(voice.name.prefix(1))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : AppTheme.accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(voice.name).font(.callout.weight(.medium))
                    if voice.isDefault {
                        Text("Default")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AppTheme.accentSoft)
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(Capsule())
                    }
                    if voice.isOutdated {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                    }
                }
                Text(voice.language).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(12)
        .background(isSelected ? AppTheme.accentSoft : AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(isSelected ? AppTheme.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
    }
}

#Preview {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var selectedVoiceID: VoiceProfile.ID?
    var body: some View {
        PracticeVoiceSelectionStepView(
            voices: .sampleMyVoices,
            selectedVoiceID: $selectedVoiceID,
            onConfirm: {}
        )
        .padding(24)
        .frame(width: 480)
    }
}
