//
//  PracticeView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import Foundation

struct PracticeFlowView: View {
    @EnvironmentObject private var voiceLibrary: VoiceLibraryStore
    @EnvironmentObject private var ttsService: QwenTTSService
    @EnvironmentObject private var scoringService: PronunciationScoringService
    @EnvironmentObject private var historyStore: HistoryStore
    @StateObject private var viewModel = PracticeViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if viewModel.flowStep == .results {
                PracticeResultsView(
                    practiceText: viewModel.practiceText,
                    recordingURL: viewModel.recordedAudioURL,
                    correctedAudioURL: viewModel.correctedAudioURL,
                    overallScore: viewModel.overallScore,
                    scoredWords: viewModel.scoredWords,
                    feedbackItems: viewModel.feedbackItems,
                    onStartNewPractice: { viewModel.resetForNewPractice() }
                )
            } else {
                wizardLayout
            }
        }
        // On the Group so it's always active — see PracticeView history-save fix.
        .onChange(of: viewModel.flowStep) { step in
            guard case .results = step else { return }
            let voiceName = voiceLibrary.voices
                .first { $0.id == viewModel.selectedVoiceID }?.name
                ?? "Unknown Voice"
            historyStore.add(viewModel.makePracticeHistoryEntry(voiceName: voiceName))
        }
    }

    // MARK: - Wizard layout

    private var wizardLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                PracticeStepperView(currentStep: stepperStep)
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppTheme.pageBackground)
        .alert("Microphone Access Needed", isPresented: $viewModel.isShowingPermissionDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pronunciation Coach needs microphone access to record your practice. You can enable it in System Settings → Privacy & Security → Microphone.")
        }
        .alert(
            "Couldn't Generate Correction",
            isPresented: Binding(
                get: { viewModel.generationError != nil },
                set: { if !$0 { viewModel.cancelGenerationAndPickAnotherVoice() } }
            )
        ) {
            Button("Retry") { viewModel.retryGeneration() }
            Button("Choose Another Voice", role: .cancel) {
                viewModel.cancelGenerationAndPickAnotherVoice()
            }
        } message: {
            Text(viewModel.generationError ?? "")
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active { viewModel.refreshMicPermission() }
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Practice").font(.title2.weight(.semibold))
            Text("Practice your pronunciation by reading the text below.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var stepperStep: PracticeStepperView.Step {
        switch viewModel.flowStep {
        case .textInput:                return .practiceText
        case .recording:                return .record
        case .selectingVoice, .generating: return .generate
        case .results:                  return .results
        }
    }

    private var selectedVoiceName: String {
        voiceLibrary.voices.first { $0.id == viewModel.selectedVoiceID }?.name
            ?? voiceLibrary.defaultVoice?.name
            ?? "Voice"
    }

    /// Status text for the generating spinner — reflects the current phase
    /// (TTS model loading, TTS inference, or Wav2Vec2 scoring).
    private var generatingStatusText: String {
        switch viewModel.generatingPhase {
        case .scoring:
            return "Analyzing your pronunciation against the baseline…"
        case .tts:
            switch ttsService.state {
            case .loadingModel:
                return "Loading the voice model — this can take a while the first time (it's downloading)."
            default:
                return "Generating correction in your voice…"
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.flowStep {
        case .textInput:
            PracticeTextInputStepView(practiceText: $viewModel.practiceText)
            HStack {
                Spacer()
                Button("Continue to Record") { viewModel.continueToRecord() }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                    .controlSize(.large)
                    .disabled(viewModel.isPracticeTextEmpty)
            }

        case .recording:
            if let startedAt = viewModel.recordingStartedAt {
                PracticeRecordingStepView(
                    practiceText: viewModel.practiceText,
                    startedAt: startedAt,
                    maxDurationSeconds: viewModel.maxRecordingSeconds,
                    isCapturingAudio: viewModel.isActuallyRecording
                ) {
                    viewModel.finishRecording(defaultVoiceID: voiceLibrary.defaultVoice?.id)
                }
            }

        case .selectingVoice:
            PracticeVoiceSelectionStepView(
                voices: voiceLibrary.voices,
                selectedVoiceID: $viewModel.selectedVoiceID,
                onConfirm: { viewModel.confirmVoiceSelection() }
            )

        case .generating:
            PracticeGeneratingStepView(
                selectedVoiceName: selectedVoiceName,
                statusText: generatingStatusText
            )
            .task(id: viewModel.generationAttempt) {
                let voice = voiceLibrary.voices.first { $0.id == viewModel.selectedVoiceID }
                await viewModel.generateCorrection(
                    ttsService: ttsService,
                    scoringService: scoringService,
                    voice: voice
                )
            }

        case .results:
            EmptyView()
        }
    }
}

#Preview {
    PracticeFlowView()
        .environmentObject(VoiceLibraryStore())
        .environmentObject(QwenTTSService())
        .environmentObject(PronunciationScoringService())
        .environmentObject(HistoryStore())
        .frame(width: 900, height: 700)
}
