//
//  CreateVoiceReferenceViewModel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

import SwiftUI
import Combine
import Foundation
import AVFoundation

/// ViewModel for the "Create Voice Reference" flow.
///
/// Revision: added `importAudioFile(from:)` so the user can supply an
/// existing audio file instead of recording live. Both paths share the
/// same `runPreprocessing(on:)` helper so the pipeline is identical.
final class CreateVoiceReferenceViewModel: ObservableObject {
    enum Step {
        case intro
        case recording
        case processing
        case review
        case naming
    }

    @Published private(set) var step: Step = .intro
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var recordingDuration: Int = 0
    @Published private(set) var recordedAudioURL: URL?
    @Published var isShowingPermissionDeniedAlert = false

    let audioRecorder = AudioRecorderService()
    let audioPlayer   = AudioPlayerService()

    private static let scripts = [
        "I wake up early every morning and make a fresh pot of coffee. I like to sit by the window, check my messages, and listen to the birds outside before starting my busy day.",
        "Today is a beautiful day to go for a walk outside. The sun is shining brightly, and the sky is very clear. I think I will wear my favorite blue shoes and a light jacket.",
        "For dinner tonight, I am going to cook a simple meal. We have some fresh chicken, a large bag of rice, and green vegetables. Later, we might share a small slice of chocolate cake.",
        "This weekend, I plan to stay home and relax with my family. We want to watch a funny movie together on the television and maybe play a few games in the living room.",
        "I need to visit the grocery store to buy some things for the house. I will get milk, fresh bread, and a few sweet apples. After that, I can finally go home and rest."
    ]
    let script: String = CreateVoiceReferenceViewModel.scripts.randomElement()!
    private let onCancelAction: () -> Void
    private let onFinishAction: (VoiceEnrollmentResult) -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        onCancel: @escaping () -> Void = {},
        onFinish: @escaping (VoiceEnrollmentResult) -> Void = { _ in }
    ) {
        self.onCancelAction = onCancel
        self.onFinishAction = onFinish

        audioRecorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        audioPlayer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        audioRecorder.$permissionStatus
            .sink { [weak self] status in
                if status == .denied { self?.isShowingPermissionDeniedAlert = true }
            }
            .store(in: &cancellables)
    }

    var isPlayingRecording: Bool { audioPlayer.isPlaying }
    var isActuallyRecording: Bool { audioRecorder.isRecording }

    func refreshMicPermission() {
        audioRecorder.refreshPermissionStatus()
        if audioRecorder.permissionStatus != .denied {
            isShowingPermissionDeniedAlert = false
        }
    }

    // MARK: - Navigation

    func cancel() {
        audioRecorder.discardRecording()
        onCancelAction()
    }

    func startRecording() {
        recordingStartedAt = Date()
        step = .recording
        audioRecorder.startRecording()
    }

    func finishRecording() {
        guard let startedAt = recordingStartedAt else { return }
        recordingDuration = max(1, Int(Date().timeIntervalSince(startedAt)))
        let rawURL = audioRecorder.stopRecording()
        runPreprocessing(on: rawURL)
    }

    /// Imports a user-chosen audio file as the voice reference.
    /// Security-scoped resources (what `.fileImporter` returns for a
    /// sandboxed app) must be copied to a temp location immediately
    /// before the scope expires, then processed through the same
    /// preprocessing pipeline as a live recording.
    func importAudioFile(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            print("CreateVoiceReferenceViewModel: failed to copy import — \(error)")
            return
        }

        if didStart { url.stopAccessingSecurityScopedResource() }

        // Derive duration from the asset (no live-recording timer here)
        let asset = AVURLAsset(url: tempURL)
        Task { @MainActor in
            if let duration = try? await asset.load(.duration) {
                let secs = Int(duration.seconds)
                self.recordingDuration = secs > 0 ? secs : 0
            }
        }

        runPreprocessing(on: tempURL)
    }

    func reRecord() {
        audioRecorder.discardRecording()
        recordedAudioURL = nil
        recordingStartedAt = nil
        step = .intro
    }

    func playRecording() {
        guard let url = recordedAudioURL else { return }
        audioPlayer.play(url: url)
    }

    func proceedToNaming() { step = .naming }

    func backToReview() { step = .review }

    func save(name: String) {
        var persistedURL: URL?
        if let recordedAudioURL {
            do {
                persistedURL = try VoiceReferenceStorage.persist(temporaryFileAt: recordedAudioURL)
            } catch {
                print("CreateVoiceReferenceViewModel: failed to persist recording — \(error)")
            }
        }
        onFinishAction(VoiceEnrollmentResult(name: name, audioURL: persistedURL, transcript: script))
    }

    // MARK: - Shared preprocessing

    /// Common path for both live recording and file import — transitions
    /// to `.processing`, runs `AudioPreprocessingService`, then moves to
    /// `.review`. Falls back to the raw file if preprocessing throws.
    private func runPreprocessing(on rawURL: URL?) {
        step = .processing

        Task {
            let resultURL: URL?
            if let rawURL {
                do {
                    resultURL = try await AudioRecordingService.trimSilenceAndDenoise(audioURL: rawURL)
                    if rawURL != resultURL {
                        try? FileManager.default.removeItem(at: rawURL)
                    }
                } catch {
                    print("CreateVoiceReferenceViewModel: preprocessing failed, using raw — \(error)")
                    resultURL = rawURL
                }
            } else {
                resultURL = nil
            }

            await MainActor.run {
                self.recordedAudioURL = resultURL
                self.step = .review
            }
        }
    }
}
