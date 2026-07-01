//
//  VoiceReferenceEmptyStateView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Matches mockup "1. Practice - Belum Ada Voice Reference".
/// Shown in the Practice tab's content area when the user has no voice
/// reference yet. UI-only for now — `onCreateVoiceReference` is a plain
/// closure so it's trivial to wire to real navigation later.
struct VoiceReferenceEmptyStateView: View {
    var onCreateVoiceReference: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard
                aboutCard
                nextStepsCard
            }
            .padding(24)
            .frame(maxWidth: 640)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBackground)
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentSoft)
                    .frame(width: 88, height: 88)
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("No voice reference yet")
                    .font(.title3.weight(.semibold))
                Text("Create a voice reference first to get corrections in your own voice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(action: onCreateVoiceReference) {
                Text("Create Voice Reference")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var aboutCard: some View {
        InfoCard(title: "What's a voice reference?") {
            ChecklistRow(text: "Corrections and examples will use your own voice")
            ChecklistRow(text: "Results feel more personal and natural")
            ChecklistRow(text: "Helps you practice more effectively")
        }
    }

    private var nextStepsCard: some View {
        InfoCard(title: "Next steps") {
            NumberedStepRow(number: 1, text: "Record your voice reference (~1 minute)")
            NumberedStepRow(number: 2, text: "We'll process your voice")
            NumberedStepRow(number: 3, text: "Your voice is ready to use for practice")
        }
    }
}

// MARK: - Small reusable pieces (kept private — only used on this screen)

private struct InfoCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

private struct ChecklistRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NumberedStepRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(AppTheme.accentSoft))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VoiceReferenceEmptyStateView()
        .frame(width: 560, height: 640)
}
