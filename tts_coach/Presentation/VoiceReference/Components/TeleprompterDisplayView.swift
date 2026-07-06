//
//  TeleprompterDisplayView.swift
//  C7-Pronunciation
//
//  Created by Savio Enoson on 20/11/25.
//


import SwiftUI

/// Display component for the teleprompter that shows sentences and highlights current one
struct TeleprompterDisplayView: View {

    let sentences: [String]
    let currentSentenceIndex: Int
    let shouldAutoScroll: Bool
    let onUserScroll: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                        SentenceRowView(
                            sentence: sentence,
                            isHighlighted: index == currentSentenceIndex,
                            isPassed: index < currentSentenceIndex
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: currentSentenceIndex) {_, newIndex in
                if shouldAutoScroll {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    onUserScroll()
                }
            )
        }
    }
}

struct SentenceRowView: View {
    @Environment(\.colorScheme) var colorScheme
    
    let sentence: String
    let isHighlighted: Bool
    let isPassed: Bool
    
    var body: some View {
        Text(sentence)
            .font(.system(size: 24, weight: isHighlighted ? .bold : .regular))
            .foregroundColor(textColor)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }
    
    private var textColor: Color {
        if isHighlighted {
            return .white
        } else if isPassed {
            return .secondary
        } else {
            return .primary
        }
    }
    
    private var backgroundColor: Color {
        if isHighlighted {
            return colorScheme == .dark ? Color.blue.opacity(0.3) : AppTheme.accent
        } else {
            return Color.clear
        }
    }
}
