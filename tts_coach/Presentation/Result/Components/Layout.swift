//
//  Layout.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// A simple left-to-right wrapping layout (like CSS `flex-wrap`).
/// Used to make a row of word "chips" wrap like a paragraph of text,
/// instead of overflowing in a single HStack. Requires macOS 13+.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !isFirstInRow, rowWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += rowHeight + verticalSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
                isFirstInRow = true
            }
            rowWidth += (isFirstInRow ? 0 : horizontalSpacing) + size.width
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight

        return CGSize(
            width: maxWidth.isFinite ? maxWidth : totalWidth,
            height: totalHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !isFirstInRow, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
                isFirstInRow = true
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
        }
    }
}

#Preview {
    FlowLayout {
        ForEach(["Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit"], id: \.self) { word in
            Text(word)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.15))
                .clipShape(Capsule())
        }
    }
    .padding()
    .frame(width: 280)
}
