//
//  VoicePageView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Full Voices page — matches mockup image 7. Master-detail layout.
/// Now backed by `VoicesPageViewModel` — this View bridges in
/// `VoiceLibraryStore` (from the environment) and passes it as a plain
/// parameter to ViewModel methods that need it, keeping the VM free of
/// environment-object coupling.
struct VoicesPageView: View {
    @EnvironmentObject private var voiceLibrary: VoiceLibraryStore
    @StateObject private var viewModel = VoicesPageViewModel()

    var body: some View {
        HStack(spacing: 0) {
            VoicesListPanel(
                myVoices: voiceLibrary.voices,
                selectedVoiceID: $viewModel.selectedVoiceID,
                onCreateVoice: { viewModel.showCreateVoice() }
            )
            .frame(width: 380)

            Divider()

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.pageBackground)
        .onAppear {
            viewModel.selectInitialVoiceIfNeeded(from: voiceLibrary.voices)
        }
        .sheet(isPresented: $viewModel.isPresentingCreateVoice) {
            CreateVoiceReferenceFlowView(
                onCancel: { viewModel.cancelCreateVoice() },
                onFinish: { result in
                    viewModel.finishCreateVoice(result, store: voiceLibrary)
                }
            )
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let index = viewModel.selectedIndex(in: voiceLibrary.voices) {
            VoiceDetailPanel(
                voice: $voiceLibrary.voices[index],
                onDelete: { viewModel.deleteVoice(at: index, from: voiceLibrary) }
            )
        } else {
            Text("Select a voice on the left")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    VoicesPageView()
        .environmentObject(VoiceLibraryStore())
        .frame(width: 1100, height: 800)
}
