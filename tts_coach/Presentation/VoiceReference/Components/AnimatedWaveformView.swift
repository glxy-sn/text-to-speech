//
//  AnimatedWaveformView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import Foundation

struct AnimatedWaveformView: View {
    var barCount: Int = 36
    var isAnimating: Bool = true
    var color: Color = AppTheme.accent

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) * 0.4
                    let height: Double = isAnimating
                        ? 8 + 18 * abs(sin(t * 2.4 + phase))
                        : 8 + 10 * abs(sin(Double(i) * 0.7))
                    Capsule()
                        .fill(color.opacity(0.8))
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 28)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        AnimatedWaveformView()
        AnimatedWaveformView(isAnimating: false)
    }
    .padding()
}
