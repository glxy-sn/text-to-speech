//
//  WordFeedback.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// One card in the "Word-by-Word Feedback" carousel — matches mockup image 6.
struct WordFeedbackCard: View {
    let item: WordFeedbackItem
    var onPlayUser: () -> Void = {}
    var onPlayTTS: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !item.phonemes.isEmpty {
                phonemeList
            }
            
            HStack(spacing: 8) {
                if item.startTime != nil {
                    Button(action: onPlayUser) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Yours")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(item.status.color.opacity(0.15))
                        .foregroundStyle(item.status.color)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                if item.ttsStartTime != nil {
                    Button(action: onPlayTTS) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Reference")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .background(item.status.color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(item.status.color.opacity(0.25))
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.word)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(item.status.color)
            }

            Spacer()

            Text("\(item.overallScore)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.status.color.opacity(0.15))
                .foregroundStyle(item.status.color)
                .clipShape(Capsule())
        }
    }

    private var phonemeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phonemes:")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            
            // Flex wrap container would be better, but ScrollView works for now
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(item.phonemes) { phoneme in
                        VStack(spacing: 2) {
                            Text(phoneme.symbol)
                                .font(.caption.monospaced())
                            Text("\(phoneme.score)")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(phoneme.status.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach([WordFeedbackItem].sampleFeedback) { item in
            WordFeedbackCard(item: item)
        }
    }
    .padding()
}
