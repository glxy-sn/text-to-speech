//
//  WordFlow.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Display mode controls how flagged words are styled:
/// - `.original`: only "needs work" / "incorrect" words get a colored pill;
///   "good" words render as plain text (matches "Your Recording" card).
/// - `.corrected`: every word renders in green with no pill (matches the
///   "Corrected (Example with Your Voice)" card — it's all "correct").
enum WordDisplayMode {
    case original
    case corrected
}

struct WordFlowText: View {
    let words: [ScoredWord]
    let mode: WordDisplayMode

    var body: some View {
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 8) {
            ForEach(words) { word in
                wordView(for: word)
            }
        }
    }

    @ViewBuilder
    private func wordView(for word: ScoredWord) -> some View {
        switch mode {
        case .corrected:
            Text(word.text)
                .font(.title3.weight(.medium))
                .foregroundStyle(.green)

        case .original:
            if word.status == .good {
                Text(word.text)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                Text(word.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(word.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(word.status.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        WordFlowText(words: .sampleRecordingWords, mode: .original)
        WordFlowText(words: .sampleRecordingWords, mode: .corrected)
    }
    .padding()
    .frame(width: 460)
}
