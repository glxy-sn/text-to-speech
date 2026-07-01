//
//  WordFeedbackCarosel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Horizontal, arrow-navigable carousel of word feedback cards, with a
/// color legend — matches mockup image 6's "Word-by-Word Feedback" section.
struct WordFeedbackCarousel: View {
    let items: [WordFeedbackItem]

    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Word-by-Word Feedback")
                    .font(.headline)
                Spacer()
                legend
            }

            HStack(spacing: 12) {
                navButton(systemName: "chevron.left") {
                    selectedIndex = max(0, selectedIndex - 1)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                WordFeedbackCard(item: item)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .leading)
                        }
                    }
                }

                navButton(systemName: "chevron.right") {
                    selectedIndex = min(items.count - 1, selectedIndex + 1)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "Good")
            legendItem(color: .orange, label: "Needs Work")
            legendItem(color: .red, label: "Incorrect")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WordFeedbackCarousel(items: [WordFeedbackItem].sampleFeedback)
        .padding()
        .frame(width: 800)
}
