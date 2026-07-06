//
//  AudioRecordServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import AVFoundation
import Combine

/// Thin wrapper around `AVAudioRecorder` for capturing microphone audio to
/// a temp file. First real Service-layer class in the project — until now
/// every "recording" in the UI was just a `Date()`-driven timer with no
/// actual audio capture underneath it.
///
/// macOS has no `AVAudioSession` (that's iOS/tvOS/watchOS only) — there's
/// no audio session category to configure, `AVAudioRecorder` just works.
/// Microphone access still needs explicit permission though, requested via
/// `AVCaptureDevice` — the same TCC-backed permission system iOS uses for
/// camera/mic, also used on macOS.
///
/// REQUIRED PROJECT SETUP (can't be done from generated source files —
/// these live in Xcode project settings, not standalone .swift files):
/// 1. Target's Info tab needs a `NSMicrophoneUsageDescription` string
///    (e.g. "Pronunciation Coach needs your microphone to record practice
///    sessions."). Without this, macOS kills the process outright instead
///    of showing a permission prompt.
/// 2. If the app is sandboxed (Signing & Capabilities tab), add the
///    "Audio Input" capability — this sets the
///    `com.apple.security.device.audio-input` entitlement. Without it,
///    recording silently fails even with the usage string in place.
///
/// No `@MainActor` on the class itself — see `VoiceLibraryStore` for why
/// that combination breaks `ObservableObject` conformance under strict
/// concurrency checking (Swift 6). Published properties are only ever
/// written from the main actor in practice (the permission callback hops
/// back via `Task { @MainActor in ... }`).
final class AudioRecorderService: NSObject, ObservableObject, @unchecked Sendable {
    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
    }

    @Published private(set) var isRecording = false
    @Published private(set) var permissionStatus: PermissionStatus = .notDetermined
    @Published private(set) var audioLevels: [Float] = Array(repeating: 0.0, count: 36)
    @Published private(set) var liveTranscription: String = ""

    private var recorder: AVAudioRecorder?
    private(set) var recordingURL: URL?
    private var meterTimer: Timer?
    private var transcriptionTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?

    /// Re-checks live authorization status without attempting to record.
    /// Useful when the app's window becomes active again — e.g. the user
    /// went to System Settings to grant mic access, then switched back —
    /// so the UI can self-heal instead of leaving a stale "denied" alert
    /// up until the next recording attempt.
    func refreshPermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionStatus = .authorized
        case .notDetermined:
            permissionStatus = .notDetermined
        case .denied, .restricted:
            permissionStatus = .denied
        @unknown default:
            permissionStatus = .denied
        }
    }

    /// Requests mic permission if needed, then starts recording to a fresh
    /// temp file. No-ops if already recording.
    func startRecording() {
        guard !isRecording else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("AudioRecorderService: authorizationStatus = authorized")
            permissionStatus = .authorized
            beginRecording()

        case .notDetermined:
            print("AudioRecorderService: authorizationStatus = notDetermined — requesting access")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    print("AudioRecorderService: requestAccess completed — granted = \(granted)")
                    self.permissionStatus = granted ? .authorized : .denied
                    if granted {
                        self.beginRecording()
                    }
                }
            }

        case .denied, .restricted:
            print("AudioRecorderService: authorizationStatus = denied/restricted")
            permissionStatus = .denied

        @unknown default:
            print("AudioRecorderService: authorizationStatus = unknown")
            permissionStatus = .denied
        }
    }

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        // 16kHz Mono PCM is perfect for Whisper and can be read live while writing
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                // If this prints, TCC permission is fine — this is a
                // device/sandbox-level failure instead (e.g. missing the
                // "Audio Input" capability/entitlement).
                print("AudioRecorderService: AVAudioRecorder.record() returned false — check the 'Audio Input' sandbox entitlement")
                return
            }
            self.recorder = recorder
            self.recordingURL = url
            self.isRecording = true
            self.liveTranscription = ""
            print("AudioRecorderService: recording started → \(url.path)")
            
            // Start meter polling timer
            DispatchQueue.main.async {
                self.audioLevels = Array(repeating: 0.0, count: 36)
                self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    self?.updateMeters()
                }
                self.transcriptionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    self?.runLiveTranscription()
                }
            }
        } catch {
            // Same as above — reaching here means TCC said yes, but the
            // recorder itself couldn't be created. Almost always a
            // sandbox/entitlement issue, not a permission-prompt issue.
            print("AudioRecorderService: failed to start recording — \(error)")
        }
    }

    /// Stops the active recording and returns the file URL it was written
    /// to. The caller now owns that file (e.g. deciding when to delete it).
    @discardableResult
    func stopRecording() -> URL? {
        guard let recorder else {
            print("AudioRecorderService: stopRecording() called with no active recorder — nothing was actually captured (likely a permission or entitlement issue upstream)")
            isRecording = false
            return nil
        }
        meterTimer?.invalidate()
        meterTimer = nil
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
        transcriptionTask?.cancel()
        
        recorder.stop()
        self.recorder = nil
        isRecording = false

        if let url = recordingURL {
            let exists = FileManager.default.fileExists(atPath: url.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            print("AudioRecorderService: stopped — file exists = \(exists), size = \(size ?? -1) bytes, path = \(url.path)")
        }
        return recordingURL
    }

    /// Stops (if needed) and deletes the temp file — used when the user
    /// discards a take to re-record, or abandons the flow entirely.
    func discardRecording() {
        meterTimer?.invalidate()
        meterTimer = nil
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
        transcriptionTask?.cancel()
        
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    private func updateMeters() {
        guard let recorder = recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        
        // Convert -60...0 dB to 0.0...1.0
        let minDb: Float = -60.0
        let normalized = max(0.0, (power - minDb) / (-minDb))
        
        audioLevels.removeFirst()
        audioLevels.append(normalized)
    }

    private func runLiveTranscription() {
        guard let url = recordingURL, isRecording else { return }
        
        // Cancel previous if still running
        transcriptionTask?.cancel()
        
        transcriptionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                // Whisper handles the growing .caf file seamlessly
                let text = try await SharedSTTService.shared.transcribe(audioURL: url)
                guard !Task.isCancelled, self.isRecording else { return }
                self.liveTranscription = text
            } catch {
                print("AudioRecorderService: live transcription error: \(error)")
            }
        }
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("AudioRecorderService: encode error — \(String(describing: error))")
        Task { @MainActor in
            self.isRecording = false
        }
    }
}
