//
//  VoiceLibrary.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

//
//  VoiceLibrary.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

import SwiftUI
import Combine

/// Shared store so the Voices page and the Practice flow can both see the
/// same voice list + settings. This is a deliberate, scoped exception to
/// "no shared state before the Model layer" — added because voice settings
/// specifically need to be visible from both places now (per your request).
/// Once a real Model/Service layer exists, this should be replaced by
/// something backed by actual persistence + the TTS/RVC backend.
///
/// No explicit `@MainActor` here on purpose — combined with
/// `ObservableObject`'s synthesized conformance, it causes a confusing
/// cascade of compiler errors under strict concurrency checking (Swift 6).
/// SwiftUI already runs this on the main thread in practice, so it's safe
/// to leave isolation to the project's default.
final class VoiceLibraryStore: ObservableObject {
    @Published var voices: [VoiceProfile] = .sampleMyVoices

    var defaultVoice: VoiceProfile? {
        voices.first(where: { $0.isDefault }) ?? voices.first
    }

    /// Builds a new `VoiceProfile` with sensible default settings and
    /// appends it — used after the Create Voice Reference flow's naming
    /// step. `sampleAudioURL` starts nil (no generated sample yet —
    /// the user needs to hit "Generate Voice" first) and
    /// `appliedTemperature`/`appliedRepetitionPenalty` match the defaults
    /// so `isOutdated` is triggered only by the missing sample, not by a
    /// false settings-drift signal.
    @discardableResult
    func addVoice(named name: String, referenceAudioURL: URL?, referenceTranscript: String?) -> VoiceProfile {
        let profile = VoiceProfile(
            name: name,
            isDefault: voices.isEmpty,
            language: "English (American)",
            createdDate: "Just now",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.9,
            repetitionPenalty: 1.5,
            referenceAudioURL: referenceAudioURL,
            referenceTranscript: referenceTranscript,
            sampleAudioURL: nil,          // no sample until "Generate Voice" is run
            appliedTemperature: 0.9,
            appliedRepetitionPenalty: 1.5
        )
        voices.append(profile)
        return profile
    }
}
