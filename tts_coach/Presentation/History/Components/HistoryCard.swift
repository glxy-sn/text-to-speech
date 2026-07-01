//
//  HistoryCard.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// One row in the History list. My own design (no mockup for this screen).
struct HistoryEntryCard: View {
    let entry: PracticeHistoryEntry
    var onTap: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ScoreBadge(score: entry.score)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(entry.textPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.caption2)
                        Text(entry.date).font(.caption2)
                        Text("•").font(.caption2)
                        Image(systemName: "mic").font(.caption2)
                        Text(entry.voiceName).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Plain button instead of Menu — Menu kept rendering an
                // extra disclosure chevron next to the ellipsis even with
                // a custom label. confirmationDialog also doubles as a
                // safety check before deleting.
                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete \"\(entry.title)\" from History?",
                    isPresented: $isShowingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive, action: onDelete)
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ScoreBadge: View {
    let score: Int

    private var color: Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(score)").font(.headline)
            Text("/100").font(.caption2)
        }
        .foregroundStyle(color)
        .frame(width: 56, height: 56)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach([PracticeHistoryEntry].sampleHistory) { entry in
            HistoryEntryCard(entry: entry)
        }
    }
    .padding()
    .frame(width: 480)
}
