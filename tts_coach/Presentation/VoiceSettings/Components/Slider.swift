//
//  Slider.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

//
//  Slider.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// "Voice Settings" sliders — shows the two parameters that
/// `generateVoiceClone` actually exposes: `temperature` and
/// `repetitionPenalty`. The four previous sliders (speechSpeed,
/// stability, similarity, styleExaggeration) were ElevenLabs/ChatterBox
/// API concepts carried over from the Python prototype; none of them map
/// to parameters in `swift-qwen3-tts`.
///
/// These bind directly to the selected `VoiceProfile`'s live values.
/// "Generate Voice" is what commits them as `applied*` — until then,
/// `isOutdated` stays true and the button stays lit.
struct VoiceSettingsSlidersSection: View {
    @Binding var voice: VoiceProfile
    var isOutdated: Bool
    var isGenerating: Bool
    var onResetToDefault: () -> Void = {}
    var onGenerateVoice: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Voice Settings")
                    .font(.headline)
                Spacer()
                Button("Reset to Default", action: onResetToDefault)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            sliderRow(
                icon: "thermometer.medium",
                title: "Temperature",
                description: "Controls how consistent vs. expressive the output sounds. Lower = more stable; higher = more varied.",
                value: $voice.temperature,
                range: 0.1...2.0,
                leadingLabel: "Stable",
                trailingLabel: "Expressive",
                format: { String(format: "%.2f", $0) }
            )

            sliderRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Repetition Penalty",
                description: "Reduces repeated speech patterns. Higher values push the model to vary its output more.",
                value: $voice.repetitionPenalty,
                range: 1.0...2.0,
                leadingLabel: "Lenient",
                trailingLabel: "Strict",
                format: { String(format: "%.2f", $0) }
            )

            generateVoiceButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generateVoiceButton: some View {
        Button(action: onGenerateVoice) {
            HStack(spacing: 6) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                }

                Text(isGenerating ? "Generating..." : "Generate Voice")

                if isOutdated && !isGenerating {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isOutdated ? AppTheme.accent : Color(nsColor: .secondaryLabelColor))
        .controlSize(.large)
        .disabled(isGenerating || !isOutdated)
    }

    private func sliderRow(
        icon: String,
        title: String,
        description: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        leadingLabel: String,
        trailingLabel: String,
        format: @escaping (Float) -> String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.medium))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: value, in: range)
                        .frame(maxWidth: .infinity)

                    HStack {
                        Text(leadingLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(trailingLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(format(value.wrappedValue))
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
                .frame(width: 56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    @State private var voice = VoiceProfile.preview

    var body: some View {
        VoiceSettingsSlidersSection(
            voice: $voice,
            isOutdated: voice.isOutdated,
            isGenerating: false
        )
        .padding()
        .frame(width: 600)
    }
}
