//
//  WaveformView.swift
//  C7-Pronunciation
//
//  Created by Jason Miracle Gunawan on 19/11/25.
//

import SwiftUI

struct WaveformView: View {
    var levels: [Float]
    var color: Color = AppTheme.accent
    var height: CGFloat? = 60
    var bottomPadding: CGFloat = 20
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            // Calculate height based on level, min height 4 so it doesn't disappear
                            .frame(height: max(geometry.size.height * CGFloat(level), 4))
                    }
                }
            }
        }
        .frame(height: height)
        .padding(.bottom, bottomPadding)
        .animation(.easeOut(duration: 0.05), value: levels)
    }
}
