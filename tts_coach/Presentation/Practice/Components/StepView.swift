//
//  StepView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// The "1 Practice Text — 2 Record — 3 Generate — 4 Results" indicator
/// shown at the top of every Practice wizard screen (mockup images 2-5).
/// Only the current step is highlighted — the mockups don't show a
/// distinct "completed" state for past steps, so we keep it simple.
struct PracticeStepperView: View {
    enum Step: Int, CaseIterable {
        case practiceText = 1
        case record = 2
        case generate = 3
        case results = 4

        var label: String {
            switch self {
            case .practiceText: return "Practice Text"
            case .record: return "Record"
            case .generate: return "Generate"
            case .results: return "Results"
            }
        }
    }

    let currentStep: Step

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases, id: \.self) { step in
                HStack(spacing: 8) {
                    badge(for: step)
                    Text(step.label)
                        .font(.callout.weight(step == currentStep ? .semibold : .regular))
                        .foregroundStyle(step == currentStep ? AppTheme.accent : .secondary)
                }
                if step != Step.allCases.last {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .frame(minWidth: 16, maxWidth: 40)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    private func badge(for step: Step) -> some View {
        let isActive = step == currentStep
        return Text("\(step.rawValue)")
            .font(.caption.weight(.bold))
            .frame(width: 22, height: 22)
            .background(Circle().fill(isActive ? AppTheme.accent : Color.clear))
            .overlay(Circle().strokeBorder(isActive ? Color.clear : Color.primary.opacity(0.2)))
            .foregroundStyle(isActive ? .white : .secondary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        PracticeStepperView(currentStep: .practiceText)
        PracticeStepperView(currentStep: .record)
        PracticeStepperView(currentStep: .generate)
        PracticeStepperView(currentStep: .results)
    }
    .padding()
    .frame(width: 520)
}
