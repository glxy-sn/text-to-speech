//
//  EmptyStateView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Shown when there's no saved practice history yet — same visual language
/// as `VoiceReferenceEmptyStateView` for consistency across the app.
struct HistoryEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.accent)

            Text("No practice history yet")
                .font(.headline)

            Text("Practice results you save will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    HistoryEmptyStateView()
        .frame(width: 500, height: 500)
}
