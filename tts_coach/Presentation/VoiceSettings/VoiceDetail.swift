//
//  VoiceDetail.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Right column of the Voices page — matches mockup image 7.
///
/// Revision: removed `VoiceDataSection` (the three stat boxes for
/// Recording Length / Sample Size / Created, plus the privacy note).
/// Those values were all placeholder dashes anyway. The "Delete Voice"
/// action is preserved — it moved inline here as a single button at the
/// bottom of the panel.
struct VoiceDetailPanel: View {
    @Binding var voice: VoiceProfile
    var onDelete: () -> Void = {}

    @StateObject private var viewModel = VoiceDetailViewModel()
    @StateObject private var audioPlayer = AudioPlayerService()
    @EnvironmentObject private var ttsService: QwenTTSService

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VoiceDetailHeaderView(voice: $voice)
                Divider()
                VoiceSampleSection(
                    durationLabel: sampleDurationLabel,
                    hasAudio: voice.sampleAudioURL != nil,
                    isPlaying: audioPlayer.isPlaying,
                    isOutdated: voice.isOutdated,
                    isGenerating: viewModel.isGenerating,
                    onPlay: {
                        if let url = voice.sampleAudioURL {
                            audioPlayer.play(url: url)
                        }
                    }
                )
                Divider()
                VoiceSettingsSlidersSection(
                    voice: $voice,
                    isOutdated: voice.isOutdated,
                    isGenerating: viewModel.isGenerating,
                    onResetToDefault: { viewModel.resetToDefault() },
                    onGenerateVoice: { viewModel.generateVoice(using: ttsService) }
                )
                Divider()

                // Delete button — confirmed via dialog before firing.
                HStack {
                    Spacer()
                    Button {
                        isShowingDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                            Text("Delete Voice…")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
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
        .alert(
            "Couldn't Generate Sample",
            isPresented: Binding(
                get: { viewModel.generationError != nil },
                set: { if !$0 { /* error clears on dismiss */ } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.generationError ?? "")
        }
        .onAppear {
            viewModel.configure(voice: $voice)
        }
        .onChange(of: voice.id) { _ in
            viewModel.configure(voice: $voice)
            audioPlayer.stop()
        }
    }

    private var sampleDurationLabel: String {
        voice.sampleAudioURL != nil ? "0:00 / —" : "—"
    }
}

#Preview {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var voice = VoiceProfile.preview
    var body: some View {
        VoiceDetailPanel(voice: $voice)
            .environmentObject(QwenTTSService())
            .frame(width: 600, height: 800)
    }
}
