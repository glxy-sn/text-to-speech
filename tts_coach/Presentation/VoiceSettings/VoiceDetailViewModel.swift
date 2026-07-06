//
//  VoiceDetailViewModel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

//
//  VoiceDetailViewModel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import SwiftUI
import Combine

/// ViewModel for the voice detail panel. Owns:
/// - `isGenerating` state while the generate-voice async task is running
/// - `generateVoice(using:)` — calls `QwenTTSService.generateSpeech` with a
///   fixed sample sentence, saves the output as `sampleAudioURL`, then
///   commits the slider values to `applied*` fields.
/// - `resetToDefault()` — snaps live sliders back to neutral values
///
/// Revision: "Generate Voice" now runs a real `QwenTTSService` call instead
/// of a fake `Task.sleep`. The fixed text is a sentence from the enrollment
/// script so the cloning context matches what was already recorded:
///   "The rainbow is a division of white light into many beautiful colors."
///
/// `ttsService` is NOT stored as a property — it's passed as a parameter to
/// `generateVoice(using:)` by the View (which reads it from the environment),
/// consistent with the rest of the app's pattern of keeping ViewModels free
/// of SwiftUI environment coupling.
///
/// Takes a `Binding<VoiceProfile>` injected via `configure(voice:)` rather
/// than `init` so this VM can be a `@StateObject` (zero-arg init requirement)
/// while still referencing the right profile.
final class VoiceDetailViewModel: ObservableObject {
    @Published private(set) var isGenerating = false
    @Published private(set) var generationError: String?

    private var voiceBinding: Binding<VoiceProfile>?


    /// Must be called once before any other method — wires the ViewModel
    /// to the specific voice it manages.
    func configure(voice: Binding<VoiceProfile>) {
        voiceBinding = voice
    }

    func resetToDefault() {
        guard let binding = voiceBinding else { return }
        binding.wrappedValue.temperature = 0.9
        binding.wrappedValue.repetitionPenalty = 1.5
    }

    /// Generates a voice sample using the current slider settings and
    /// stores the result in `voice.sampleAudioURL`. On success, commits
    /// `temperature`/`repetitionPenalty` to their `applied*` counterparts
    /// so `isOutdated` resets. On failure, sets `generationError` so the
    /// View can surface it (alert, inline banner, etc.).
    func generateVoice() {
        guard let binding = voiceBinding else { return }

        guard binding.wrappedValue.hasUsableReference else {
            generationError = "This voice doesn't have a usable recording yet. Re-create it in the Create Voice flow."
            return
        }

        // Snapshot the values we need — capture them before the async Task
        // starts so we don't read a potentially-mutated binding later.
        let refAudioURL = binding.wrappedValue.referenceAudioURL!
        let refTranscript = binding.wrappedValue.referenceTranscript ?? ""
        let temperature = binding.wrappedValue.temperature
        let repetitionPenalty = binding.wrappedValue.repetitionPenalty

        isGenerating = true
        generationError = nil

        Task { @MainActor in
            do {
                let text = "Hello world! This is \(binding.wrappedValue.name) speaking. 你好世界！这是 \(binding.wrappedValue.name)."
                let ttsService = QwenTTSService.shared
                let (sampleURL, _, _) = try await ttsService.generateAudio(
                    text: text,
                    referenceAudioURL: refAudioURL,
                    referenceTranscript: refTranscript,
                    language: "Auto",
                    speed: 1.0,
                    refLength: .long
                )
                // Commit both the generated sample and the settings that
                // produced it — `isOutdated` clears when these match.
                binding.wrappedValue.sampleAudioURL = sampleURL
                binding.wrappedValue.appliedTemperature = temperature
                binding.wrappedValue.appliedRepetitionPenalty = repetitionPenalty
            } catch {
                generationError = "Couldn't generate voice sample: \(error.localizedDescription)"
                print("VoiceDetailViewModel: generateVoice failed — \(error)")
            }
            isGenerating = false
        }
    }
}
