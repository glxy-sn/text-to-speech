//
//  HeaderView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Top of the detail panel — matches mockup image 7's right column header.
/// The pencil button now actually works: tapping it turns the name into
/// an editable field (just the name — nothing else here is editable).
struct VoiceDetailHeaderView: View {
    @Binding var voice: VoiceProfile

    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 56, height: 56)
                .overlay(
                    Text(voice.name.prefix(1))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("Voice name", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: 220)
                            .focused($isNameFieldFocused)
                            .onSubmit { commitEdit() }

                        Button(action: commitEdit) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                        .buttonStyle(.plain)

                        Button(action: cancelEdit) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(voice.name).font(.title3.weight(.semibold))

                        if voice.isDefault {
                            Text("Default")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accentSoft)
                                .foregroundStyle(AppTheme.accent)
                                .clipShape(Capsule())
                        }

                        Button(action: startEditing) {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("\(voice.language) • Created \(voice.createdDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Used for pronunciation examples and text-to-speech playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func startEditing() {
        editedName = voice.name
        isEditingName = true
        isNameFieldFocused = true
    }

    private func commitEdit() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            voice.name = trimmed
        }
        isEditingName = false
    }

    private func cancelEdit() {
        isEditingName = false
    }
}

#Preview {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var voice = VoiceProfile.preview
    var body: some View {
        VoiceDetailHeaderView(voice: $voice)
            .padding()
            .frame(width: 600)
    }
}
