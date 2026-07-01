//
//  VoicePageViewModel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import SwiftUI
import Combine

/// Page-level ViewModel for the Voices page. Owns:
/// - which voice is selected (master-detail selection)
/// - whether the Create Voice sheet is open
/// - the deletion action (confirmed upstream by `VoiceDataSection`)
///
/// `VoiceLibraryStore` is passed into every method that needs it rather
/// than stored as a property — same reasoning as `PracticeViewModel`:
/// keeps this class free of SwiftUI-specific environment mechanisms so
/// it's easy to test standalone.
final class VoicesPageViewModel: ObservableObject {
    @Published var selectedVoiceID: VoiceProfile.ID?
    @Published var isPresentingCreateVoice = false

    /// Called on `.onAppear` — selects the first voice if nothing is
    /// selected yet (e.g. fresh launch or after every voice was deleted).
    func selectInitialVoiceIfNeeded(from voices: [VoiceProfile]) {
        if selectedVoiceID == nil {
            selectedVoiceID = voices.first?.id
        }
    }

    func showCreateVoice() {
        isPresentingCreateVoice = true
    }

    func cancelCreateVoice() {
        isPresentingCreateVoice = false
    }

    /// Called when the Create Voice flow's naming step finishes.
    /// Hands the result (name + persisted audio + transcript) to `store`
    /// to construct & persist the profile, then selects it immediately so
    /// the detail panel opens on it.
    func finishCreateVoice(_ result: VoiceEnrollmentResult, store: VoiceLibraryStore) {
        isPresentingCreateVoice = false
        let newVoice = store.addVoice(
            named: result.name,
            referenceAudioURL: result.audioURL,
            referenceTranscript: result.transcript
        )
        selectedVoiceID = newVoice.id
    }

    /// `VoiceDataSection` already showed the confirmation dialog before
    /// calling this — here we remove it, clean up its persisted audio
    /// file (if any), and move selection if needed.
    func deleteVoice(at index: Int, from store: VoiceLibraryStore) {
        let voice = store.voices[index]
        if let audioURL = voice.referenceAudioURL {
            VoiceReferenceStorage.delete(audioURL)
        }
        store.voices.remove(at: index)
        if selectedVoiceID == voice.id {
            selectedVoiceID = store.voices.first?.id
        }
    }

    func selectedIndex(in voices: [VoiceProfile]) -> Int? {
        voices.firstIndex { $0.id == selectedVoiceID }
    }
}
