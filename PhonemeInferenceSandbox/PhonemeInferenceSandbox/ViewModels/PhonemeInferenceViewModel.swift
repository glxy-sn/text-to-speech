import Foundation
import CoreML
import Combine
import AVFoundation
import MLXAudioCore
import MLXAudioTTS

public enum TTSEngine: String, CaseIterable, Identifiable {
    case qwen = "Qwen3"
    case cosyvoice = "CosyVoice3"
    public var id: String { self.rawValue }
}

@MainActor
class PhonemeInferenceViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var targetScript: String = "The vibrant bands of red, orange, yellow, green, blue, and violet curve gracefully across the sky..."
    @Published var selectedEngine: TTSEngine = .qwen
    @Published var extractedPhonemes: [String] = []
    @Published var targetWordAlignments: [(word: String, phonemeIndices: [Int])] = []
    @Published var userRawPhonemes: [String] = []
    @Published var phoneScores: [PhoneScore] = []
    @Published var wordScores: [WordScore] = []
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String = ""
    @Published var isModelLoading: Bool = false
    @Published var error: String? = nil
    @Published var isRecording: Bool = false
    @Published var isPlaying: Bool = false
    @Published var generatedAudioURL: URL? = nil

    // Performance Metrics
    @Published var generationTTFA: Double? = nil
    @Published var generationRTF: Double? = nil

    // Pace Metadata (CosyVoice only)
    @Published var detectedWPM: Double? = nil
    @Published var normFactor: Double? = nil
    @Published var finalSpeed: Double? = nil

    // Voice Parameters
    @Published var selectedCloneVoice: String = "savio"
    @Published var availableVoices: [String] = []

    // Generation Parameters
    @Published var selectedLanguage: String = "Auto-Select"
    @Published var speed: Float = 1.0
    @Published var refLength: TTSRefLength = .short

    let availableLanguages = ["Auto-Select", "English", "Mandarin"]
    
    private var baselineASRTimings: [SpeechAlignmentService.WordTiming] = []
    private var phonemesWithFrames: [(symbol: String, frame: Int)] = []

    private var engine: AudioInferenceEngine?
    private var scorer: AlignmentScorerEngine
    private var recordingService = AudioRecordingService()
    private var audioPlayer: AVAudioPlayer?

    override init() {
        self.scorer = AlignmentScorerEngine()
        super.init()
        self.loadAvailableVoices()
    }
    
    public func recalculatePhonemeAlignments() {
        guard !phonemesWithFrames.isEmpty else { return }
        
        self.targetWordAlignments = PhonemeWordAligner.alignHybrid(targetScript: self.targetScript, asrTimings: self.baselineASRTimings, phonemes: self.phonemesWithFrames)
        
        // Re-calculate word scores if phone scores exist
        if !phoneScores.isEmpty {
            self.wordScores = self.targetWordAlignments.map { alignment in
                let scoresForWord = alignment.phonemeIndices.compactMap { idx in 
                    idx < phoneScores.count ? phoneScores[idx] : nil
                }
                let avg = scoresForWord.isEmpty ? 0.0 : scoresForWord.map { $0.gopScore }.reduce(0, +) / Float(scoresForWord.count)
                return WordScore(word: alignment.word, phoneScores: scoresForWord, averageScore: avg)
            }
        }
    }

    private func loadAvailableVoices() {
        if let urls = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil) {
            self.availableVoices = urls.map { $0.deletingPathExtension().lastPathComponent }.filter { !$0.starts(with: "test_reference") }.sorted()
            if !self.availableVoices.contains(selectedCloneVoice), let first = availableVoices.first {
                selectedCloneVoice = first
            }
        } else {
            self.availableVoices = ["savio"]
        }
    }

    func loadModel() async {
        guard self.engine == nil else { return }

        self.isModelLoading = true
        self.statusMessage = "Loading TTS Models..."

        do {
            try await QwenTTSService.shared.initialize()

            // Check CosyVoice connection silently on boot
            do {
                try await CosyVoiceTTSService.shared.initialize()
            } catch {
                print("CosyVoice offline check: \(error.localizedDescription)")
            }

            self.statusMessage = "Loading Evaluation Model (Wav2Vec2)..."

            let loadedEngine: AudioInferenceEngine
            if let modelURL = Bundle.main.url(forResource: "Wav2Vec2Phonetic", withExtension: "mlmodelc") {
                loadedEngine = try await AudioInferenceEngine.load(modelURL: modelURL)
            } else {
                let url = URL(fileURLWithPath: "Wav2Vec2Phonetic.mlmodelc")
                if FileManager.default.fileExists(atPath: url.path) {
                    loadedEngine = try await AudioInferenceEngine.load(modelURL: url)
                } else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Wav2Vec2Phonetic.mlmodelc not found in bundle."])
                }
            }

            self.engine = loadedEngine
            self.statusMessage = "Ready. Enter script to begin."
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
            self.statusMessage = ""
        }

        self.isModelLoading = false
    }

    func invalidateBaseline() {
        self.generatedAudioURL = nil
        self.extractedPhonemes = []
        self.targetWordAlignments = []
        self.userRawPhonemes = []
        self.phoneScores = []
        self.wordScores = []
        self.generationTTFA = nil
        self.generationRTF = nil
        self.detectedWPM = nil
        self.normFactor = nil
        self.finalSpeed = nil
        self.statusMessage = "Configuration changed. Generate baseline again."
    }

    func generateBaseline() {
        guard !targetScript.isEmpty else {
            self.error = "Target script cannot be empty."
            return
        }
        guard self.engine != nil else {
            self.error = "Model not initialized."
            return
        }

        self.isProcessing = true
        self.error = nil
        self.extractedPhonemes = []
        self.targetWordAlignments = []
        self.userRawPhonemes = []
        self.phoneScores = []
        self.wordScores = []
        self.generationTTFA = nil
        self.generationRTF = nil
        self.detectedWPM = nil
        self.normFactor = nil
        self.finalSpeed = nil
        self.statusMessage = "Streaming TTS Baseline..."
        self.isPlaying = true

        Task {
            do {
                // Resolve reference audio from bundle
                var cloneURL: URL? = nil
                if let url = Bundle.main.url(forResource: selectedCloneVoice, withExtension: "wav", subdirectory: nil) {
                    cloneURL = url
                }

                let resultURL: URL

                switch selectedEngine {
                case .qwen:
                    // Map "Auto-Select" to the "Auto" string Qwen expects
                    let qwenLanguage = selectedLanguage == "Auto-Select" ? "Auto" : selectedLanguage
                    let (url, ttfa, rtf) = try await QwenTTSService.shared.generateAudio(
                        text: targetScript,
                        referenceAudioURL: cloneURL,
                        isMultiLanguage: false,
                        language: qwenLanguage,
                        speed: speed,
                        refLength: refLength
                    )
                    resultURL = url
                    self.generationTTFA = ttfa
                    self.generationRTF = rtf

                case .cosyvoice:
                    if await !CosyVoiceTTSService.shared.isReady {
                        try await CosyVoiceTTSService.shared.initialize()
                    }
                    let cosyResult = try await CosyVoiceTTSService.shared.generateAudio(
                        text: targetScript,
                        referenceAudioURL: cloneURL,
                        language: cosyLanguageCode(for: selectedLanguage),
                        speed: speed,
                        refLength: refLength
                    )
                    resultURL = cosyResult.audioURL
                    self.generationTTFA = cosyResult.ttfa
                    self.generationRTF = cosyResult.rtf
                    self.detectedWPM = cosyResult.detectedWPM
                    self.normFactor = cosyResult.normFactor
                    self.finalSpeed = cosyResult.finalSpeed
                }

                self.generatedAudioURL = resultURL // Store original for playback
                
                // Preprocess the baseline audio to remove hallucinations and standardize tempo for Wav2Vec2
                let trimmedURL = try await AudioRecordingService.trimSilenceAndDenoise(audioURL: resultURL)
                let processedURL = try await AudioRecordingService.normalizeTempo(audioURL: trimmedURL, targetScript: self.targetScript, targetWPM: 130.0)

                guard let engine = self.engine else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Wav2Vec2 Engine not initialized"])
                }

                let multiArray = try AudioService.loadAudio(from: processedURL)
                let phonemesWithFrames = try engine.extractTargetPhonemes(from: multiArray)
                let phonemes = phonemesWithFrames.map { $0.symbol }
                self.extractedPhonemes = phonemes
                
                let hasChinese = self.targetScript.range(of: "\\p{Han}", options: .regularExpression) != nil
                let locale = selectedLanguage == "Mandarin" || (selectedLanguage == "Auto-Select" && hasChinese) ? "zh-CN" : "en-US"
                
                do {
                    let asrTimings = try await SpeechAlignmentService.getWordTimings(audioURL: processedURL, localeIdentifier: locale)
                    self.baselineASRTimings = SpeechAlignmentService.alignTimingsToTarget(targetScript: self.targetScript, asrTimings: asrTimings)
                } catch {
                    print("Speech alignment failed: \(error)")
                    self.baselineASRTimings = []
                }
                
                self.phonemesWithFrames = phonemesWithFrames
                self.recalculatePhonemeAlignments()

                
                self.statusMessage = "Ready. Tap Record or Upload."
                self.isPlaying = false
            } catch {
                self.error = "Baseline Generation failed: \(error.localizedDescription)"
                self.statusMessage = ""
                self.isPlaying = false
            }
            self.isProcessing = false
        }
    }

    func startRecording() {
        guard !isProcessing, !extractedPhonemes.isEmpty else { return }
        self.error = nil
        self.phoneScores = []
        self.wordScores = []
        Task {
            do {
                try await recordingService.startRecording()
                self.isRecording = true
                self.statusMessage = "Listening..."
            } catch {
                self.error = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopRecordingAndScore() {
        guard isRecording else { return }
        recordingService.stopRecording()
        self.isRecording = false
        self.statusMessage = "Scoring pronunciation..."
        self.isProcessing = true

        Task {
            // Need to wait briefly for file writing to flush
            try? await Task.sleep(nanoseconds: 500_000_000)

            guard let url = recordingService.recordingURL else {
                self.error = "No recording found."
                self.isProcessing = false
                self.statusMessage = "Ready. Hold to Speak."
                return
            }

            do {
                let normalizedURL = try await AudioRecordingService.normalizeTempo(audioURL: url, targetScript: self.targetScript)
                
                guard let engine = engine else { throw NSError(domain: "", code: 0) }
                let multiArray = try AudioService.loadAudio(from: normalizedURL)
                let logits = try engine.extractUserLogits(from: multiArray)

                let greedyResult = engine.runGreedyDecodeWithFrames(logits: logits)
                self.userRawPhonemes = greedyResult.map { $0.symbol }

                let scores = scorer.scorePronunciation(userLogits: logits, targetPhonemes: self.extractedPhonemes, vocabulary: engine.vocabulary, greedyAnchors: greedyResult)

                self.phoneScores = scores
                self.wordScores = self.targetWordAlignments.map { alignment in
                    let scoresForWord = alignment.phonemeIndices.compactMap { idx in 
                        idx < scores.count ? scores[idx] : nil
                    }
                    let avg = scoresForWord.isEmpty ? 0.0 : scoresForWord.map { $0.gopScore }.reduce(0, +) / Float(scoresForWord.count)
                    return WordScore(word: alignment.word, phoneScores: scoresForWord, averageScore: avg)
                }
                
                self.statusMessage = "Scoring complete. Hold to retry."
            } catch {
                self.error = "Scoring failed: \(error.localizedDescription)"
                self.statusMessage = "Ready. Tap Record or Upload."
            }
            self.isProcessing = false
        }
    }

    func playGeneratedAudio() {
        guard let url = generatedAudioURL else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            self.error = "Playback failed: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        if isProcessing {
            Task {
                switch selectedEngine {
                case .qwen:
                    await QwenTTSService.shared.stopAudio()
                case .cosyvoice:
                    await CosyVoiceTTSService.shared.stopAudio()
                }
            }
        }
        audioPlayer?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }

    func scoreUploadedAudio(url: URL) {
        guard !isProcessing, !extractedPhonemes.isEmpty else { return }
        self.error = nil
        self.phoneScores = []
        self.wordScores = []
        self.isProcessing = true
        self.statusMessage = "Scoring uploaded audio..."

        Task {
            do {
                guard let engine = engine else { throw NSError(domain: "", code: 0) }
                let multiArray = try AudioService.loadAudio(from: url)
                let logits = try engine.extractUserLogits(from: multiArray)

                let greedyResult = engine.runGreedyDecodeWithFrames(logits: logits)
                self.userRawPhonemes = greedyResult.map { $0.symbol }

                let scores = scorer.scorePronunciation(userLogits: logits, targetPhonemes: self.extractedPhonemes, vocabulary: engine.vocabulary, greedyAnchors: greedyResult)

                self.phoneScores = scores
                self.wordScores = self.targetWordAlignments.map { alignment in
                    let scoresForWord = alignment.phonemeIndices.compactMap { idx in 
                        idx < scores.count ? scores[idx] : nil
                    }
                    let avg = scoresForWord.isEmpty ? 0.0 : scoresForWord.map { $0.gopScore }.reduce(0, +) / Float(scoresForWord.count)
                    return WordScore(word: alignment.word, phoneScores: scoresForWord, averageScore: avg)
                }
                
                self.statusMessage = "Scoring complete. Tap Record or Upload to retry."
            } catch {
                self.error = "Scoring failed: \(error.localizedDescription)"
                self.statusMessage = "Ready. Tap Record or Upload."
            }
            self.isProcessing = false
        }
    }

    // MARK: - Private Helpers

    /// Maps the UI language selection to the backend target_language code.
    private func cosyLanguageCode(for language: String) -> String {
        switch language {
        case "Mandarin": return "chinese"
        default:         return "auto"
        }
    }
}
