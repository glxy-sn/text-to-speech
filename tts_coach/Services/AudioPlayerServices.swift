//
//  AudioPlayerServices.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import AVFoundation
import Combine

/// Thin wrapper around `AVAudioPlayer` for previewing a recorded audio
/// file. Pairs with `AudioRecorderService` — several review screens
/// (`VoiceRefReviewStepView`, the "Your Recording" card in
/// `PracticeResultsView`) had a play button with a `// TODO: wire to real
/// playback once audio Service exists` comment; this is that Service.
///
/// No `@MainActor` on the class itself, same reasoning as
/// `AudioRecorderService`/`VoiceLibraryStore`.
final class AudioPlayerService: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentLevels: [Float] = Array(repeating: 0.1, count: 60)

    private var player: AVAudioPlayer?
    @Published private(set) var currentURL: URL?

    private var stopTimer: Timer?
    private var meterTimer: Timer?

    /// Plays `url`. If this exact file is already loaded, toggles
    /// pause/resume instead of restarting from scratch — lets a single
    /// "play" button double as play/pause without the View needing to
    /// track playback state itself.
    func play(url: URL) {
        stopTimer?.invalidate()
        stopTimer = nil
        
        if currentURL == url, let player {
            if player.isPlaying {
                player.pause()
                stopMetering()
                isPlaying = false
            } else {
                player.play()
                startMetering()
                isPlaying = true
            }
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.isMeteringEnabled = true
            player.play()
            self.player = player
            self.currentURL = url
            self.isPlaying = true
            startMetering()
        } catch {
            print("AudioPlayerService: failed to play \(url) — \(error)")
        }
    }

    /// Plays a specific time segment of the audio file.
    func playSegment(url: URL, startTime: TimeInterval, endTime: TimeInterval) {
        stopTimer?.invalidate()
        stopTimer = nil

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.isMeteringEnabled = true
            player.currentTime = max(0, startTime)
            player.play()
            self.player = player
            self.currentURL = url
            self.isPlaying = true
            startMetering()

            let duration = endTime - startTime
            if duration > 0 {
                stopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                    self?.stop()
                }
            }
        } catch {
            print("AudioPlayerService: failed to play segment of \(url) — \(error)")
        }
    }

    func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        stopMetering()
        player?.stop()
        isPlaying = false
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        DispatchQueue.main.async {
            self.currentLevels = Array(repeating: 0.1, count: 60)
        }
    }

    private func updateMeters() {
        guard let player = player, player.isPlaying else { return }
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)
        let level = max(0.1, min(1.0, (power + 80.0) / 80.0))
        DispatchQueue.main.async {
            self.currentLevels.removeFirst()
            self.currentLevels.append(level)
        }
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopMetering()
            self.isPlaying = false
        }
    }
}
