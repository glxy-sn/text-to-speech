//
//  RecordingStepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//
import SwiftUI
import Foundation
import Combine

/// Step 2 of the Practice wizard — matches mockup image 3.
/// Timer is derived from `startedAt` via `TimelineView`, same pattern as
/// the Voice Reference recording step.
///
/// `isCapturingAudio` reflects whether `AudioRecorderService` is genuinely
/// capturing right now — separate from this countdown, which is purely
/// cosmetic. If they disagree, a warning banner shows instead of
/// silently producing an empty recording.
struct PracticeRecordingStepView: View {
    let practiceText: String
    let startedAt: Date
    let maxDurationSeconds: Int
    var isCapturingAudio: Bool = true
    var audioLevels: [Float] = Array(repeating: 0.0, count: 36)
    var liveTranscription: String = ""
    var onFinish: () -> Void

    @State private var userScrolled = false
    @State private var elapsedSeconds: Int = 0
    @State private var activeWordIndex: Int = 0
    @State private var hasFinished = false

    private var teleprompterData: [TeleprompterSentence] {
        var text = practiceText
        text = text.replacingOccurrences(of: ", ", with: ",|")
        text = text.replacingOccurrences(of: ". ", with: ".|")
        text = text.replacingOccurrences(of: "; ", with: ";|")
        text = text.replacingOccurrences(of: ": ", with: ":|")
        
        let sentenceStrings = text.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            
        var data = [TeleprompterSentence]()
        var currentGlobalWordIndex = 0
        for (i, s) in sentenceStrings.enumerated() {
            let words = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            data.append(TeleprompterSentence(id: i, text: s, words: words, startWordIndex: currentGlobalWordIndex))
            currentGlobalWordIndex += words.count
        }
        return data
    }
    
    private func updateActiveWordIndex() {
        let spokenWords = liveTranscription.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let proposedIndex = spokenWords.count
        var newIndex = activeWordIndex
        
        if proposedIndex > activeWordIndex {
            // Cap forward jump to +3 words at a time to prevent jarring skips
            let jump = min(proposedIndex - activeWordIndex, 3)
            newIndex = activeWordIndex + jump
        }
        
        let totalWords = teleprompterData.last.map { $0.startWordIndex + $0.words.count } ?? 0
        newIndex = min(newIndex, max(0, totalWords - 1))
        
        // Final block confidence check: only finish if we hear the end of the text
        if newIndex >= totalWords - 1 && totalWords > 0 && !hasFinished {
            let cleanScript = teleprompterData.map { $0.text }.joined().lowercased()
                .components(separatedBy: .punctuationCharacters).joined()
                .replacingOccurrences(of: " ", with: "")
                
            let cleanTranscript = liveTranscription.lowercased()
                .components(separatedBy: .punctuationCharacters).joined()
                .replacingOccurrences(of: " ", with: "")
                
            let length = cleanScript.count
            let hearsFinalBlock: Bool
            
            if length >= 6 {
                let end1 = String(cleanScript.suffix(4))
                let end2 = String(cleanScript.dropLast(2).suffix(4))
                hearsFinalBlock = cleanTranscript.contains(end1) || cleanTranscript.contains(end2)
            } else {
                hearsFinalBlock = cleanScript.isEmpty || cleanTranscript.contains(cleanScript)
            }
            
            if hearsFinalBlock {
                hasFinished = true
                onFinish()
            } else {
                // Hold at the penultimate word until we hear the final block
                newIndex = max(0, totalWords - 2)
            }
        }
        
        if newIndex != activeWordIndex {
            activeWordIndex = newIndex
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Record Your Voice").font(.headline)
                Text("Read the text below clearly and naturally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TeleprompterDisplayView(
                sentences: teleprompterData,
                activeWordIndex: activeWordIndex,
                shouldAutoScroll: !userScrolled
            )
            .frame(height: 200)
            .background(AppTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            recordingWidget

            if !isCapturingAudio {
                capturingWarningBanner
            }

            tipsRow
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { date in
            elapsedSeconds = min(maxDurationSeconds, max(0, Int(date.timeIntervalSince(startedAt))))
            updateActiveWordIndex()
        }
        .onChange(of: liveTranscription) { _, _ in
            updateActiveWordIndex()
        }
    }

    private var recordingWidget: some View {
        VStack(spacing: 10) {
            ZStack {
                WaveformView(levels: audioLevels.isEmpty ? Array(repeating: 0.0, count: 36) : audioLevels)
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.white)
                    )
            }

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = min(maxDurationSeconds, max(0, Int(context.date.timeIntervalSince(startedAt))))
                Text("\(timeString(elapsed)) / \(timeString(maxDurationSeconds))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Button("Finish Recording", action: onFinish)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var capturingWarningBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Microphone isn't capturing audio. Check mic permission in System Settings, then try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tipsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            Text("Tip: Make sure your environment is quiet and your microphone is working well.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    PracticeRecordingStepView(
        practiceText: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
        startedAt: Date(),
        maxDurationSeconds: 120,
        onFinish: {}
    )
    .padding(24)
    .frame(width: 480)
}
