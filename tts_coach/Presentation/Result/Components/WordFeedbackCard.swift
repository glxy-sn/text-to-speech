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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch item.content {
            case .needsReview(_, let youSaid, let expected, let tip):
                detailContent(youSaid: youSaid, expected: expected, tip: tip)
            case .good:
                praiseContent
            }
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
        .background(item.status.color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(item.status.color.opacity(0.25))
        )
    }

    private var header: some View {
        HStack {
            Text(item.word)
                .font(.title3.weight(.bold))
                .foregroundStyle(item.status.color)

            Spacer()

            if case .needsReview(let score, _, _, _) = item.content {
                Text("\(score)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.status.color.opacity(0.15))
                    .foregroundStyle(item.status.color)
                    .clipShape(Capsule())
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(item.status.color)
            }
        }
    }

    private func detailContent(youSaid: String, expected: String, tip: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ipaRow(label: "You said", ipa: youSaid)
            ipaRow(label: "Expected", ipa: expected)
            VStack(alignment: .leading, spacing: 4) {
                Text("Tip").font(.caption.weight(.semibold))
                Text(tip).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var praiseContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Great!").font(.callout.weight(.semibold))
            Text("You pronounced this word clearly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ipaRow(label: String, ipa: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(ipa).font(.callout)
            }
            Spacer()
            Button(action: { /* TODO: wire to real playback once audio Service exists */ }) {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
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
