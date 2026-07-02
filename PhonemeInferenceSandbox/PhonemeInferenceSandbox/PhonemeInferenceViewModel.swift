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
    @Published var userRawPhonemes: [String] = []
    @Published var phoneScores: [PhoneScore] = []
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
    
    // Voice Parameters
    @Published var selectedCloneVoice: String = "savio"
    @Published var availableVoices: [String] = []
    
    // Generation Parameters
    @Published var isMultiLanguage: Bool = false
    @Published var selectedLanguage: String = "Auto"
    @Published var speed: Float = 1.0
    
    let availableLanguages = ["Auto", "English", "Mandarin", "Japanese", "Korean", "Cantonese"]
    
    private var engine: AudioInferenceEngine?
    private var scorer: AlignmentScorerEngine
    private var recordingService = AudioRecordingService()
    private var audioPlayer: AVAudioPlayer?
    
    override init() {
        self.scorer = AlignmentScorerEngine()
        super.init()
        self.loadAvailableVoices()
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
        self.userRawPhonemes = []
        self.phoneScores = []
        self.generationTTFA = nil
        self.generationRTF = nil
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
        self.userRawPhonemes = []
        self.phoneScores = []
        self.generationTTFA = nil
        self.generationRTF = nil
        self.statusMessage = "Streaming TTS Baseline..."
        self.isPlaying = true
        
        Task {
            do {
                // Load reference audio
                var cloneURL: URL? = nil
                if let url = Bundle.main.url(forResource: selectedCloneVoice, withExtension: "wav", subdirectory: nil) {
                    cloneURL = url
                }
                
                // Native in-process synthesis with live streaming
                let resultURL: URL
                
                switch selectedEngine {
                case .qwen:
                    let (url, ttfa, rtf) = try await QwenTTSService.shared.generateAudio(
                        text: targetScript,
                        referenceAudioURL: cloneURL,
                        isMultiLanguage: isMultiLanguage,
                        language: selectedLanguage,
                        speed: speed
                    )
                    resultURL = url
                    self.generationTTFA = ttfa
                    self.generationRTF = rtf
                case .cosyvoice:
                    if await !CosyVoiceTTSService.shared.isReady {
                        try await CosyVoiceTTSService.shared.initialize()
                    }
                    let (url, ttfa, rtf) = try await CosyVoiceTTSService.shared.generateAudio(
                        text: targetScript,
                        referenceAudioURL: cloneURL,
                        isMultiLanguage: isMultiLanguage,
                        language: selectedLanguage,
                        speed: speed
                    )
                    
                    self.generationTTFA = ttfa
                    self.generationRTF = rtf
                    resultURL = url
                }
                
                self.generatedAudioURL = resultURL
                
                guard let engine = self.engine else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Wav2Vec2 Engine not initialized"])
                }
                
                let multiArray = try AudioService.loadAudio(from: resultURL)
                let phonemes = try engine.extractTargetPhonemes(from: multiArray)
                self.extractedPhonemes = phonemes
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
        do {
            try recordingService.startRecording()
            self.isRecording = true
            self.statusMessage = "Listening..."
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
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
                guard let engine = engine else { throw NSError(domain: "", code: 0) }
                let multiArray = try AudioService.loadAudio(from: url)
                let logits = try engine.extractUserLogits(from: multiArray)
                
                let greedyResult = engine.runGreedyDecodeWithFrames(logits: logits)
                self.userRawPhonemes = greedyResult.map { $0.symbol }
                
                let scores = scorer.scorePronunciation(userLogits: logits, targetPhonemes: self.extractedPhonemes, vocabulary: engine.vocabulary, greedyAnchors: greedyResult)
                
                self.phoneScores = scores
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
                self.statusMessage = "Scoring complete. Tap Record or Upload to retry."
            } catch {
                self.error = "Scoring failed: \(error.localizedDescription)"
                self.statusMessage = "Ready. Tap Record or Upload."
            }
            self.isProcessing = false
        }
    }
}
