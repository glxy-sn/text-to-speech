//
//  VoiceModels.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

//
//  VoiceModels.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// UI-only data types for the Voices page. Not the real domain Model yet —
/// real voice profiles (and their RVC/ChatterBox-backed settings) will come
/// from the Model/Service layer once that's built.
///
/// Revision: replaced the four ChatterBox/ElevenLabs-era sliders
/// (speechSpeed, stability, similarity, styleExaggeration) with the two
/// parameters that `swift-qwen3-tts`'s `generateVoiceClone` actually
/// exposes: `temperature` and `repetitionPenalty`. The old names were
/// ElevenLabs API concepts carried over from the Python backend prototype;
/// they have no corresponding parameters in the on-device model.
///
/// Also added `sampleAudioURL` — the URL of the TTS-generated preview
/// clip (from "Generate Voice"), stored separately from
/// `referenceAudioURL` (the enrollment recording). Previously the sample
/// player in `VoiceDetail` played the raw enrollment recording; now it
/// plays the generated sample instead.

struct VoiceProfile: Identifiable {
    let id = UUID()
    var name: String
    let isDefault: Bool
    let language: String
    let createdDate: String
    let recordingLength: String
    let sampleSize: String

    /// Sampling temperature for `generateVoiceClone`. Lower = more
    /// consistent/stable output; higher = more expressive/variable.
    /// Range 0.1 – 2.0, model default 0.9.
    var temperature: Float

    /// Repetition penalty for `generateVoiceClone`. Higher values push
    /// the model to avoid repeating speech patterns.
    /// Range 1.0 – 2.0, model default 1.5.
    var repetitionPenalty: Float

    /// Permanent on-disk location of the recorded enrollment audio (see
    /// `VoiceReferenceStorage`), and the exact text that was read aloud
    /// while recording it. Both are required for real voice cloning via
    /// `QwenTTSService` (`refAudio`/`refText`).
    ///
    /// `nil` for voices that were seeded without a real recording.
    var referenceAudioURL: URL?
    var referenceTranscript: String?

    /// URL of the generated TTS preview clip — produced by "Generate
    /// Voice" using the fixed sample sentence. This is what `VoiceSampleSection`
    /// plays, not `referenceAudioURL`. `nil` until the user hits
    /// "Generate Voice" for the first time.
    var sampleAudioURL: URL?

    /// Snapshot of the settings that were in effect during the last
    /// "Generate Voice" pass. If the live values above differ from this
    /// snapshot (or no sample has been generated yet), `isOutdated` is
    /// true and the "Generate Voice" button lights up.
    var appliedTemperature: Float
    var appliedRepetitionPenalty: Float

    /// True when there's no sample yet, or when the live slider values
    /// have diverged from the last generate pass. In either case the
    /// "Generate Voice" button should be enabled.
    var isOutdated: Bool {
        sampleAudioURL == nil
            || temperature != appliedTemperature
            || repetitionPenalty != appliedRepetitionPenalty
    }

    /// Whether this profile has everything `QwenTTSService` needs to
    /// actually clone this voice, as opposed to just being display data.
    var hasUsableReference: Bool {
        referenceAudioURL != nil
    }
}

/// What `CreateVoiceReferenceViewModel` hands back once the user finishes
/// naming a freshly-recorded voice — everything a caller needs to turn it
/// into a real, usable `VoiceProfile` via `VoiceLibraryStore.addVoice`.
struct VoiceEnrollmentResult {
    let name: String
    let audioURL: URL?
    let transcript: String
}

struct SampleVoice: Identifiable {
    let id = UUID()
    let name: String
    let language: String
}

// MARK: - Sample data

extension Array where Element == VoiceProfile {
    static let sampleMyVoices: [VoiceProfile] = [
        VoiceProfile(
            name: "Dewa",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "dewa", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arc",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Gagaz",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "gagaz", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arc, with its",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Kak Anggi",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "kak_anggi", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors.",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Kak Gemala",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "kak_gemala", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Kak Tere",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "kak_tere", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Ko Davin",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "ko_davin", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Nicholas",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "nicholas", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. This takes the shape of a long round arch with its path high up.",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Savio",
            isDefault: true,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "savio", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arc, with its path high",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        ),
        VoiceProfile(
            name: "Tiara",
            isDefault: false,
            language: "Indonesian",
            createdDate: "Prepackaged",
            recordingLength: "—",
            sampleSize: "—",
            temperature: 0.7,
            repetitionPenalty: 1.0,
            referenceAudioURL: Bundle.main.url(forResource: "tiara", withExtension: "wav"),
            referenceTranscript: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arc,",
            sampleAudioURL: nil,
            appliedTemperature: 0.7,
            appliedRepetitionPenalty: 1.0
        )
    ]
}

extension VoiceProfile {
    /// Preview-only stand-in so `#Preview` blocks across the Voices
    /// feature have something to render. Never used by the running app.
    static let preview = VoiceProfile(
        name: "Preview Voice",
        isDefault: true,
        language: "English (American)",
        createdDate: "Just now",
        recordingLength: "0 min 45 sec",
        sampleSize: "—",
        temperature: 0.9,
        repetitionPenalty: 1.5,
        referenceAudioURL: nil,
        referenceTranscript: nil,
        sampleAudioURL: nil,
        appliedTemperature: 0.9,
        appliedRepetitionPenalty: 1.5
    )
}

extension Array where Element == SampleVoice {
    static let sampleSystemVoices: [SampleVoice] = [
        SampleVoice(name: "Samantha", language: "English (American)"),
        SampleVoice(name: "James", language: "English (British)")
    ]
}
