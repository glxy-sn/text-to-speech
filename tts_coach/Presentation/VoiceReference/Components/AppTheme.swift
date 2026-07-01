//
//  AppTheme.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI
import AppKit

enum AppTheme {
    static let accent = Color(hex: 0x6C5CE7)
    static let accentSoft = Color(hex: 0x6C5CE7).opacity(0.12)

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)

    static let cardCornerRadius: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
