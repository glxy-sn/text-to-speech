//
//  appTab.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// The top-level sidebar destinations. Settings was explicitly dropped
/// from scope, so it's Practice / History / Voices.
enum AppTab: String, CaseIterable, Identifiable {
    case practice = "Practice"
    case history = "History"
    case voices = "Voices"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .practice: return "house"
        case .history: return "clock"
        case .voices: return "mic"
        }
    }
}
