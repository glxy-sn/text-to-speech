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

    private var player: AVAudioPlayer?
    private var currentURL: URL?

    /// Plays `url`. If this exact file is already loaded, toggles
    /// pause/resume instead of restarting from scratch — lets a single
    /// "play" button double as play/pause without the View needing to
    /// track playback state itself.
    func play(url: URL) {
        if currentURL == url, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            self.currentURL = url
            self.isPlaying = true
        } catch {
            print("AudioPlayerService: failed to play \(url) — \(error)")
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
