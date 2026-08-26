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

                Picker("TTS Engine", selection: $viewModel.selectedEngine) {
                    ForEach(TTSEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.top, Catalyst.Spacing.sm)

                // Reference Length — applies to all TTS engines
                CatalystFormGroup(label: "Reference Length") {
                    VStack(alignment: .leading, spacing: Catalyst.Spacing.sm) {
                        Text("How much of the reference audio to use for voice cloning.")
                            .font(Catalyst.Typography.caption1)
                            .foregroundColor(Catalyst.Text.secondary(colorScheme))
                        Picker("Reference Length", selection: $viewModel.refLength) {
                            ForEach(TTSRefLength.allCases) { length in
                                Text(length.displayName).tag(length)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                


                if viewModel.selectedEngine == .cosyvoice {
                    CatalystFormGroup(label: "Model Parameters") {
                        VStack(alignment: .leading, spacing: Catalyst.Spacing.md) {

                            // Language
                            Picker("Target Language", selection: $viewModel.selectedLanguage) {
                                ForEach(viewModel.availableLanguages, id: \.self) { lang in
                                    Text(lang).tag(lang)
                                }
                            }

                            // Speed
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Speed (x\(String(format: "%.2f", viewModel.speed)))")
                                    .font(Catalyst.Typography.caption1)
                                    .foregroundColor(Catalyst.Text.secondary(colorScheme))
                                Slider(value: $viewModel.speed, in: 0.5...2.0, step: 0.1)
                            }
                        }
                    }
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

                    // Performance & pace metrics
                    if viewModel.generationTTFA != nil || viewModel.detectedWPM != nil {
                        VStack(alignment: .trailing, spacing: 2) {
                            if let ttfa = viewModel.generationTTFA, let rtf = viewModel.generationRTF {
                                HStack(spacing: Catalyst.Spacing.md) {
                                    Label(String(format: "TTFA %.2fs", ttfa), systemImage: "clock")
                                    Label(String(format: "RTF %.2fx", rtf), systemImage: "speedometer")
                                }
                                .font(Catalyst.Typography.caption1.monospacedDigit())
                                .foregroundColor(Catalyst.Text.secondary(colorScheme))
                            }
                            if viewModel.selectedEngine == .cosyvoice {
                                HStack(spacing: Catalyst.Spacing.md) {
                                    if let wpm = viewModel.detectedWPM {
                                        Label(String(format: "%.0f WPM", wpm), systemImage: "waveform")
                                    }
                                    if let norm = viewModel.normFactor {
                                        Label(String(format: "Norm ×%.2f", norm), systemImage: "dial.medium")
                                    }
                                    if let fs = viewModel.finalSpeed {
                                        Label(String(format: "Speed ×%.2f", fs), systemImage: "gauge.with.dots.needle.67percent")
                                    }
                                }
                                .font(Catalyst.Typography.caption1.monospacedDigit())
                                .foregroundColor(Catalyst.Text.secondary(colorScheme))
                            }
                        }
                        .padding(.horizontal, Catalyst.Spacing.sm)
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

                        if viewModel.wordScores.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Catalyst.Spacing.md) {
                                    ForEach(Array(viewModel.targetWordAlignments.enumerated()), id: \.offset) { index, alignment in
                                        VStack(alignment: .leading, spacing: Catalyst.Spacing.sm) {
                                            Text(alignment.word)
                                                .font(Catalyst.Typography.headline)
                                                .fontWeight(.bold)
                                            
                                            HStack(spacing: 2) {
                                                ForEach(alignment.phonemeIndices, id: \.self) { idx in
                                                    if idx < viewModel.extractedPhonemes.count {
                                                        Text(viewModel.extractedPhonemes[idx])
                                                            .font(Catalyst.Typography.caption1.monospaced())
                                                            .padding(.horizontal, 4)
                                                            .padding(.vertical, 2)
                                                            .background(Color.gray.opacity(0.2))
                                                            .cornerRadius(Catalyst.Radius.sm)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(Catalyst.Spacing.md)
                                        .background(Catalyst.Surface.surface(colorScheme))
                                        .cornerRadius(Catalyst.Radius.md)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        } else {
                            // Present scores
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Catalyst.Spacing.md) {
                                    ForEach(viewModel.wordScores) { wordScore in
                                        VStack(alignment: .leading, spacing: Catalyst.Spacing.sm) {
                                            HStack {
                                                Text(wordScore.word)
                                                    .font(Catalyst.Typography.headline)
                                                    .fontWeight(.bold)
                                                Spacer()
                                                Text(String(format: "%.2f", wordScore.averageScore))
                                                    .font(Catalyst.Typography.caption1)
                                                    .foregroundColor(Catalyst.Text.secondary(colorScheme))
                                            }
                                            
                                            HStack(spacing: 2) {
                                                ForEach(wordScore.phoneScores) { phoneScore in
                                                    VStack(spacing: 2) {
                                                        Text(phoneScore.symbol)
                                                            .font(Catalyst.Typography.caption1.monospaced())
                                                        Text(String(format: "%.2f", phoneScore.gopScore))
                                                            .font(.system(size: 8).monospacedDigit())
                                                    }
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(backgroundColor(for: phoneScore.gopScore))
                                                    .foregroundColor(Catalyst.Text.primary(colorScheme))
                                                    .cornerRadius(Catalyst.Radius.sm)
                                                }
                                            }
                                        }
                                        .padding(Catalyst.Spacing.md)
                                        .background(Catalyst.Surface.surface(colorScheme))
                                        .cornerRadius(Catalyst.Radius.md)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Catalyst.Radius.md)
                                                .stroke(backgroundColor(for: wordScore.averageScore), lineWidth: 2)
                                        )
                                    }
                                }
                                .padding(.bottom, 8)
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
