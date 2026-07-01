//
//  ListPanel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Left column of the Voices page — matches mockup image 7.
struct VoicesListPanel: View {
    let myVoices: [VoiceProfile]
    @Binding var selectedVoiceID: VoiceProfile.ID?
    var onCreateVoice: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                sectionHeader("My Voices")
                VStack(spacing: 12) {
                    ForEach(myVoices) { voice in
                        Button {
                            selectedVoiceID = voice.id
                        } label: {
                            VoiceListItemCard(voice: voice, isSelected: voice.id == selectedVoiceID)
                        }
                        .buttonStyle(.plain)
                    }
                }

                            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voices").font(.largeTitle.weight(.bold))
                Text("Manage your voice profiles used for pronunciation examples.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onCreateVoice) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Create Voice")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline)
    }
}

#Preview {
    VoicesListPanel(
        myVoices: .sampleMyVoices,
        selectedVoiceID: .constant([VoiceProfile].sampleMyVoices.first?.id)
    )
    .frame(width: 380, height: 700)
}
