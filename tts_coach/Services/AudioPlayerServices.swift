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

    private var meterTimer: Timer?
    private var segmentEndTime: TimeInterval?

    /// Plays `url`. If this exact file is already loaded, toggles
    /// pause/resume instead of restarting from scratch — lets a single
    /// "play" button double as play/pause without the View needing to
    /// track playback state itself.
    func play(url: URL) {
        if currentURL == url, let player {
            if player.isPlaying {
                player.pause()
                stopMetering()
                isPlaying = false
            } else {
                // If we last played a segment, or we are at the end, reset to start
                if segmentEndTime != nil || player.currentTime >= (player.duration - 0.1) {
                    player.currentTime = 0
                }
                segmentEndTime = nil
                player.play()
                startMetering()
                isPlaying = true
            }
            return
        }

        do {
            player?.stop()
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.isMeteringEnabled = true
            newPlayer.play()
            self.player = newPlayer
            self.currentURL = url
            self.segmentEndTime = nil
            self.isPlaying = true
            startMetering()
        } catch {
            print("AudioPlayerService: failed to play \(url) — \(error)")
        }
    }

    /// Plays a specific time segment of the audio file.
    func playSegment(url: URL, startTime: TimeInterval, endTime: TimeInterval) {
        player?.stop()

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.isMeteringEnabled = true
            newPlayer.currentTime = max(0, startTime)
            newPlayer.play()
            self.player = newPlayer
            self.currentURL = url
            self.segmentEndTime = endTime
            self.isPlaying = true
            startMetering()
        } catch {
            print("AudioPlayerService: failed to play segment of \(url) — \(error)")
        }
    }

    func stop() {
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
        
        // Accurate segment boundary check
        if let segmentEnd = segmentEndTime, player.currentTime >= segmentEnd {
            self.stop()
            return
        }
        
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)
        let minDb: Float = -45.0
        let level = max(0.1, min(1.0, (power - minDb) / (-minDb)))
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
