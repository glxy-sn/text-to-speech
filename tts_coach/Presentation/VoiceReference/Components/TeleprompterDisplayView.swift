//
//  TeleprompterDisplayView.swift
//  C7-Pronunciation
//
//  Created by Savio Enoson on 20/11/25.
//


import SwiftUI

struct TeleprompterSentence: Identifiable, Equatable {
    let id: Int
    let text: String
    let words: [String]
    let startWordIndex: Int
}

/// Display component for the teleprompter that shows sentences and highlights current one
struct TeleprompterDisplayView: View {

    let sentences: [TeleprompterSentence]
    let activeWordIndex: Int
    let shouldAutoScroll: Bool
    
    var body: some View {
        let activeSentenceIndex = sentences.firstIndex { s in
            activeWordIndex >= s.startWordIndex && activeWordIndex < (s.startWordIndex + s.words.count)
        } ?? (sentences.count - 1)
        
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sentences) { sentence in
                        SentenceRowView(
                            sentence: sentence,
                            activeWordIndex: activeWordIndex
                        )
                        .id(sentence.id)
                    }
                }
                .padding()
            }
            .onChange(of: activeSentenceIndex) {_, newIndex in
                if shouldAutoScroll {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

struct SentenceRowView: View {
    @Environment(\.colorScheme) var colorScheme
    
    let sentence: TeleprompterSentence
    let activeWordIndex: Int
    
    var body: some View {
        let sentenceIsActive = activeWordIndex >= sentence.startWordIndex && activeWordIndex < (sentence.startWordIndex + sentence.words.count)
        let sentenceIsPassed = activeWordIndex >= (sentence.startWordIndex + sentence.words.count)
        
        var combined = Text("")
        for (i, word) in sentence.words.enumerated() {
            let globalIndex = sentence.startWordIndex + i
            let isHighlighted = globalIndex == activeWordIndex
            let isPassed = globalIndex < activeWordIndex
            
            var wordText = Text(word + " ")
                .font(.system(size: 24, weight: isHighlighted ? .bold : .regular))
            
            if isHighlighted {
                wordText = wordText.foregroundColor(.white)
            } else if isPassed {
                wordText = wordText.foregroundColor(.secondary.opacity(0.5))
            } else {
                wordText = wordText.foregroundColor(.primary)
            }
            
            combined = combined + wordText
        }
        
        return combined
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isActive: sentenceIsActive))
            )
            .animation(.easeInOut(duration: 0.2), value: sentenceIsActive)
    }
    
    private func backgroundColor(isActive: Bool) -> Color {
        if isActive {
            return colorScheme == .dark ? Color.blue.opacity(0.3) : AppTheme.accent
        } else {
            return Color.clear
        }
    }
}
