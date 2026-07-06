//
//  PracticeViewModel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

import SwiftUI
import Combine
import Foundation

/// ViewModel for the Practice wizard.
///
/// Revision: `makePracticeHistoryEntry` now copies both audio files
/// (user recording + TTS correction) from the temp directory to a
/// permanent location in Application Support before building the
/// history entry. Temp files disappear on every app restart, so
/// anything stored in history must live somewhere more stable.
///
/// Storage path: `Application Support/PronunciationCoach/HistoryAudio/<sessionID>/`
/// Each session gets its own subfolder (named by UUID) so there are
/// no filename collisions between sessions.
final class PracticeViewModel: ObservableObject {

    // MARK: - Flow state

    enum FlowStep {
        case textInput, recording, selectingVoice, generating, results
    }

    enum GeneratingPhase {
        case tts
        case scoring
    }

    @Published private(set) var flowStep: FlowStep = .textInput
    @Published private(set) var generatingPhase: GeneratingPhase = .tts

    // MARK: - Practice data

    @Published var practiceText: String = "Practice makes perfect. 孰能生巧."
    
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var recordingDuration: Int = 0
    @Published private(set) var recordedAudioURL: URL?
    @Published private(set) var correctedAudioURL: URL?
    @Published var selectedVoiceID: VoiceProfile.ID?

    // MARK: - Scoring results

    @Published private(set) var overallScore: Int = 0
    @Published private(set) var scoredWords: [ScoredWord] = []
    @Published private(set) var feedbackItems: [WordFeedbackItem] = []

    // MARK: - UI state

    @Published var isShowingPermissionDeniedAlert = false
    @Published private(set) var generationError: String?
    @Published private(set) var generationAttempt = 0

    let audioRecorder = AudioRecorderService()
    let maxRecordingSeconds = 120

    private var cancellables = Set<AnyCancellable>()

    init() {
        audioRecorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        audioRecorder.$permissionStatus
            .sink { [weak self] status in
                if status == .denied { self?.isShowingPermissionDeniedAlert = true }
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed helpers

    var isPracticeTextEmpty: Bool {
        practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var isActuallyRecording: Bool { audioRecorder.isRecording }

    // MARK: - Flow actions

    func refreshMicPermission() {
        audioRecorder.refreshPermissionStatus()
        if audioRecorder.permissionStatus != .denied { isShowingPermissionDeniedAlert = false }
    }

    func continueToRecord() {
        recordingStartedAt = Date()
        flowStep = .recording
        audioRecorder.startRecording()
    }

    func finishRecording(defaultVoiceID: VoiceProfile.ID?) {
        guard let startedAt = recordingStartedAt else { return }
        recordingDuration = max(1, Int(Date().timeIntervalSince(startedAt)))
        recordedAudioURL  = audioRecorder.stopRecording()
        if selectedVoiceID == nil { selectedVoiceID = defaultVoiceID }
        flowStep = .selectingVoice
    }

    func confirmVoiceSelection() { flowStep = .generating }

    func generateCorrection(
        scoringService: PronunciationScoringService,
        voice: VoiceProfile?
    ) async {
        guard flowStep == .generating else { return }

        guard let voice,
              let audioURL = voice.referenceAudioURL else {
            await MainActor.run {
                self.generationError = "This voice doesn't have a usable recording yet. Create or pick a different voice in the Voices tab."
            }
            return
        }

        do {
            await MainActor.run { self.generatingPhase = .tts }

            let ttsService = QwenTTSService.shared
            let (ttsURL, _, _) = try await ttsService.generateAudio(
                text: practiceText,
                referenceAudioURL: audioURL,
                referenceTranscript: voice.referenceTranscript,
                language: "Auto",
                speed: 1.0,
                refLength: .long
            )
            await MainActor.run { self.correctedAudioURL = ttsURL }

            await MainActor.run { self.generatingPhase = .scoring }

            if let userAudioURL = recordedAudioURL {
                do {
                    let result = try await scoringService.score(
                        practiceText: practiceText,
                        userRecordingURL: userAudioURL,
                        ttsAudioURL: ttsURL
                    )
                    await MainActor.run {
                        self.overallScore  = result.overallScore
                        self.scoredWords   = result.scoredWords
                        self.feedbackItems = result.feedbackItems
                    }
                } catch {
                    print("PracticeViewModel: scoring failed gracefully — \(error.localizedDescription)")
                    await MainActor.run {
                        self.overallScore  = 0
                        self.scoredWords   = .allGood(from: self.practiceText)
                        self.feedbackItems = []
                    }
                }
            } else {
                await MainActor.run { self.scoredWords = .allGood(from: self.practiceText) }
            }

            await MainActor.run {
                if self.flowStep == .generating { self.flowStep = .results }
            }
        } catch {
            await MainActor.run { self.generationError = error.localizedDescription }
        }
    }

    func retryGeneration() {
        generationError = nil
        generationAttempt += 1
    }

    func cancelGenerationAndPickAnotherVoice() {
        generationError = nil
        flowStep = .selectingVoice
    }

    func resetForNewPractice() {
        audioRecorder.discardRecording()
        recordedAudioURL   = nil
        correctedAudioURL  = nil
        generationError    = nil
        overallScore       = 0
        scoredWords        = []
        feedbackItems      = []
        generatingPhase    = .tts
        flowStep           = .textInput
        recordingStartedAt = nil
        recordingDuration  = 0
        selectedVoiceID    = nil
    }

    // MARK: - History

    /// Builds a `PracticeHistoryEntry` for the just-completed session.
    ///
    /// Audio files are copied from the temp directory to Application Support
    /// BEFORE the entry is created, so the URLs in the entry will still be
    /// valid after the app is restarted. Both copies are best-effort — if
    /// a copy fails, that URL is just `nil` in the entry (play button
    /// silently does nothing) rather than blocking the save.
    func makePracticeHistoryEntry(voiceName: String) -> PracticeHistoryEntry {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let preview  = String(practiceText.prefix(80))
        let rawTitle = String(practiceText.prefix(40))
        let title    = practiceText.count > 40 ? rawTitle + "…" : rawTitle

        // Each session gets a unique subfolder so concurrent sessions
        // (or replays) don't overwrite each other's files.
        let sessionID = UUID().uuidString
        let permanentRecording  = Self.copyAudioToHistory(recordedAudioURL,  named: "recording.m4a",    sessionID: sessionID)
        let permanentCorrection = Self.copyAudioToHistory(correctedAudioURL, named: "correction.wav",   sessionID: sessionID)

        return PracticeHistoryEntry(
            title: title,
            date: "Today, \(timeFormatter.string(from: Date()))",
            score: overallScore,
            textPreview: preview,
            voiceName: voiceName,
            recordingWords: scoredWords.isEmpty ? .allGood(from: practiceText) : scoredWords,
            feedbackItems: feedbackItems,
            recordingURL: permanentRecording,
            correctedAudioURL: permanentCorrection
        )
    }

    /// Copies `source` to `Application Support/PronunciationCoach/HistoryAudio/<sessionID>/<fileName>`.
    /// Returns the destination URL on success, `nil` on failure.
    private static func copyAudioToHistory(_ source: URL?, named fileName: String, sessionID: String) -> URL? {
        guard let source else { return nil }

        do {
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let sessionDir = appSupport
                .appendingPathComponent("PronunciationCoach")
                .appendingPathComponent("HistoryAudio")
                .appendingPathComponent(sessionID)

            try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)

            let destination = sessionDir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
            return destination
        } catch {
            print("PracticeViewModel: failed to persist '\(fileName)' for history — \(error.localizedDescription)")
            return nil
        }
    }
}
