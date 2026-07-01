//
//  ListCard.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// One row in the "My Voices" list — matches mockup image 7.
struct VoiceListItemCard: View {
    let voice: VoiceProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? AppTheme.accent : AppTheme.accentSoft)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(voice.name.prefix(1))
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : AppTheme.accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(voice.name).font(.callout.weight(.semibold))
                    if voice.isDefault {
                        Text("Default")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentSoft)
                            .foregroundStyle(AppTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                Text("Created \(voice.createdDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "mic")
                        .font(.caption2)
                    Text(voice.language)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            AnimatedWaveformView(
                barCount: 12,
                isAnimating: false,
                color: isSelected ? AppTheme.accent : Color(nsColor: .secondaryLabelColor)
            )
            .frame(width: 56)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(isSelected ? AppTheme.accentSoft : AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(isSelected ? AppTheme.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        VoiceListItemCard(voice: VoiceProfile.preview, isSelected: true)
        VoiceListItemCard(voice: VoiceProfile.preview, isSelected: false)
    }
    .padding()
    .frame(width: 360)
}
