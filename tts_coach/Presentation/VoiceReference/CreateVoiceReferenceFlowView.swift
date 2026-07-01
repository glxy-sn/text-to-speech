//
//  CreateVoiceReferenceFlowView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// The "Create Voice Reference" modal — matches mockup image 8.
///
/// Revision: added `@State isShowingFilePicker` and `.fileImporter`
/// so the intro step can offer "Upload Audio File" as an alternative
/// to recording live. The file picker lives here (not inside
/// `VoiceRefIntroStepView`) because it must be in the hierarchy
/// at all times — it's attached to the else-branch VStack which
/// covers every step except .naming, so it's always present when
/// the user could conceivably trigger it from the intro step.
struct CreateVoiceReferenceFlowView: View {
    @StateObject private var viewModel: CreateVoiceReferenceViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingFilePicker = false

    init(
        onCancel: @escaping () -> Void = {},
        onFinish: @escaping (VoiceEnrollmentResult) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: CreateVoiceReferenceViewModel(onCancel: onCancel, onFinish: onFinish)
        )
    }

    var body: some View {
        if viewModel.step == .naming {
            SaveResultDialogView(
                title: "Save this voice as...",
                defaultName: "My Voice",
                onCancel: { viewModel.backToReview() },
                onSave: { name in viewModel.save(name: name) }
            )
        } else {
            VStack(spacing: 0) {
                closeButtonRow
                content
                    .padding(28)
            }
            .frame(width: 420)
            .alert(
                "Microphone Access Needed",
                isPresented: $viewModel.isShowingPermissionDeniedAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pronunciation Coach needs microphone access to record your voice. You can enable it in System Settings → Privacy & Security → Microphone.")
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active { viewModel.refreshMicPermission() }
            }
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { viewModel.importAudioFile(from: url) }
                case .failure(let error):
                    print("CreateVoiceReferenceFlowView: file picker failed — \(error)")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .intro:
            VoiceRefIntroStepView(
                script: viewModel.script,
                onUploadAudio: { isShowingFilePicker = true }
            ) {
                viewModel.startRecording()
            }

        case .recording:
            if let startedAt = viewModel.recordingStartedAt {
                VoiceRefRecordingStepView(
                    script: viewModel.script,
                    startedAt: startedAt,
                    isCapturingAudio: viewModel.isActuallyRecording
                ) {
                    viewModel.finishRecording()
                }
            }

        case .processing:
            VoiceRefProcessingStepView()

        case .review:
            VoiceRefReviewStepView(
                script: viewModel.script,
                durationSeconds: viewModel.recordingDuration,
                isPlaying: viewModel.isPlayingRecording,
                onPlay: { viewModel.playRecording() },
                onReRecord: { viewModel.reRecord() },
                onNext: { viewModel.proceedToNaming() }
            )

        case .naming:
            // Unreachable — body handles .naming directly with SaveResultDialogView.
            EmptyView()
        }
    }

    private var closeButtonRow: some View {
        HStack {
            Spacer()
            Button(action: { viewModel.cancel() }) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding([.top, .trailing], 16)
        }
    }
}

#Preview {
    CreateVoiceReferenceFlowView()
        .frame(width: 700, height: 600)
}
