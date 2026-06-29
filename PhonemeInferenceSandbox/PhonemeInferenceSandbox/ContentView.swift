import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = PhonemeInferenceViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.catalystAccent) private var accent
    @State private var isImporterPresented = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Catalyst.Spacing.lg) {
                Text("E2E Speech Correction")
                    .font(Catalyst.Typography.largeTitle)
                
                if let error = viewModel.error {
                    CatalystAlertBanner(.danger, message: error, title: "Error")
                }
                
                CatalystFormGroup(label: "Reference Voice") {
                    Picker("Select Reference Voice", selection: $viewModel.selectedCloneVoice) {
                        ForEach(viewModel.availableVoices, id: \.self) { voice in
                            Text(voice.replacingOccurrences(of: "_", with: " ").capitalized).tag(voice)
                        }
                    }
                }
                
                CatalystFormGroup(label: "Target Script") {
                    TextField("Enter what you want to say...", text: $viewModel.targetScript, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(Catalyst.Typography.body)
                        .padding()
                        .background(Catalyst.Surface.surface(colorScheme))
                        .cornerRadius(Catalyst.Radius.md)
                        .lineLimit(3...6)
                }
                
                HStack {
                    CatalystButton("Generate Baseline", role: .primary) {
                        viewModel.generateBaseline()
                    }
                    .disabled(viewModel.isModelLoading || (viewModel.isProcessing && viewModel.extractedPhonemes.isEmpty))
                    
                    if viewModel.generatedAudioURL != nil {
                        CatalystButton(viewModel.isPlaying ? "Stop Audio" : "Play Audio", role: .default) {
                            if viewModel.isPlaying {
                                viewModel.stopPlayback()
                            } else {
                                viewModel.playGeneratedAudio()
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if viewModel.isModelLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 4)
                    }
                    
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(Catalyst.Typography.caption1)
                            .foregroundColor(Catalyst.Text.secondary(colorScheme))
                    }
                }
                
                if !viewModel.extractedPhonemes.isEmpty {
                    Divider().padding(.vertical, Catalyst.Spacing.md)
                    
                    VStack(alignment: .leading, spacing: Catalyst.Spacing.md) {
                        Text("Pronunciation Assessment")
                            .font(Catalyst.Typography.title2)
                        
                        if viewModel.phoneScores.isEmpty {
                            Text(viewModel.extractedPhonemes.joined(separator: " "))
                                .font(Catalyst.Typography.mono)
                                .padding()
                                .background(Catalyst.Surface.surface(colorScheme))
                                .cornerRadius(Catalyst.Radius.md)
                        } else {
                            // Present scores
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Catalyst.Spacing.sm) {
                                    ForEach(viewModel.phoneScores) { score in
                                        VStack(spacing: Catalyst.Spacing.sm) {
                                            Text("\(score.symbol) (\(score.frames)f)")
                                                .font(Catalyst.Typography.mono)
                                                .fontWeight(.bold)
                                            Text(String(format: "%.2f", score.gopScore))
                                                .font(Catalyst.Typography.caption1)
                                        }
                                        .padding(Catalyst.Spacing.sm)
                                        .background(backgroundColor(for: score.gopScore))
                                        .foregroundColor(Catalyst.Text.primary(colorScheme))
                                        .cornerRadius(Catalyst.Radius.sm)
                                    }
                                }
                            }
                            
                            if !viewModel.userRawPhonemes.isEmpty {
                                VStack(alignment: .leading, spacing: Catalyst.Spacing.sm) {
                                    Text("Raw Phonemes Heard:")
                                        .font(Catalyst.Typography.caption1)
                                        .foregroundColor(Catalyst.Text.secondary(colorScheme))
                                    Text(viewModel.userRawPhonemes.joined(separator: " "))
                                        .font(Catalyst.Typography.mono)
                                        .padding()
                                        .background(Catalyst.Surface.surface(colorScheme))
                                        .cornerRadius(Catalyst.Radius.md)
                                }
                                .padding(.top, Catalyst.Spacing.md)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: Catalyst.Spacing.md) {
                            Spacer()
                            
                            CatalystButton(viewModel.isRecording ? "Stop & Score" : "Start Recording", role: viewModel.isRecording ? .danger : .primary) {
                                if viewModel.isRecording {
                                    viewModel.stopRecordingAndScore()
                                } else {
                                    viewModel.startRecording()
                                }
                            }
                            
                            CatalystButton("Upload Audio", role: .default) {
                                isImporterPresented = true
                            }
                            
                            Spacer()
                        }
                        .padding(.top, Catalyst.Spacing.lg)
                        .disabled(viewModel.isProcessing)
                    }
                }
                
                Spacer()
            }
            .padding(Catalyst.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Catalyst.Surface.bg(colorScheme))
        .task {
            await viewModel.loadModel()
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.wav]) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    viewModel.scoreUploadedAudio(url: url)
                    url.stopAccessingSecurityScopedResource()
                } else {
                    viewModel.scoreUploadedAudio(url: url)
                }
            case .failure(let error):
                viewModel.error = "File upload failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func backgroundColor(for score: Float) -> Color {
        if score > 0.8 {
            return Catalyst.success.fill(colorScheme).opacity(0.8)
        } else if score > 0.5 {
            return Catalyst.warning.fill(colorScheme).opacity(0.8)
        } else {
            return Catalyst.danger.fill(colorScheme).opacity(0.8)
        }
    }

}
