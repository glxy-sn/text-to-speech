//
//  InputStepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//


import SwiftUI

/// Step 1 of the Practice wizard — matches mockup image 2.
///
/// Revision: removed the "Upload PDF" tab. It was always a stub with no
/// real implementation and no plan for one in this build cycle — keeping
/// a permanently-broken UI option around is more confusing than dropping
/// it.
struct PracticeTextInputStepView: View {
    @Binding var practiceText: String

    private var characterCount: Int { practiceText.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Practice Text")
                .font(.headline)

            textEditorBox
            tipsBanner
        }
    }

    private var textEditorBox: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $practiceText)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 160)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08))
                )

            HStack {
                Button("Clear") { practiceText = "" }
                    .buttonStyle(.bordered)

                Spacer()

                Text("Characters: \(characterCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tipsBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundStyle(AppTheme.accent)
            Text("Tip: Ideal text length is 50 - 300 words for the best correction results.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    PracticeTextInputStepView(practiceText: .constant(
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
    ))
    .padding(24)
    .frame(width: 480)
}
