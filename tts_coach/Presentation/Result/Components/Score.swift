//
//  Score.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Circular score gauge — matches the "82/100" ring in mockup image 6.
struct ScoreRingView: View {
    let score: Int

    private var progress: Double {
        min(1, max(0, Double(score) / 100))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 26, weight: .bold))
                Text("/100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
    }
}

#Preview {
    ScoreRingView(score: 82)
        .padding()
}
