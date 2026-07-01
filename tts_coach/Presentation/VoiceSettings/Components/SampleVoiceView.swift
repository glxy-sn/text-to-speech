//
//  SampleVoiceView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// "Voice Sample" playback row — matches mockup image 7, plus an
/// "Outdated" badge + generating state added per the Generate Voice
/// revision, and real playback (per a later revision) via whatever
/// `AudioPlayerService` the caller wires up.
struct VoiceSampleSection: View {
    let durationLabel: String
    var hasAudio: Bool = true
    var isPlaying: Bool = false
    var isOutdated: Bool = false
    var isGenerating: Bool = false
    var onPlay: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Voice Sample").font(.headline)
                if isOutdated && !isGenerating {
                    Text("Outdated")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            if isGenerating {
                generatingRow
            } else {
                playbackRow
            }

            Text(captionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var captionText: String {
        if isGenerating {
            return "Regenerating the voice sample with the latest settings..."
        } else if !hasAudio {
            return "No recording is available for this voice yet."
        } else if isOutdated {
            return "This voice sample still uses the old settings. Press \"Generate Voice\" to update it."
        } else {
            return "This is how your voice will sound when reading text."
        }
    }

    private var playbackRow: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .disabled(!hasAudio)

            AnimatedWaveformView(barCount: 50, isAnimating: isPlaying)

            Text(durationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .opacity(hasAudio ? 1 : 0.5)
    }

    private var generatingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Generating voice sample...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

#Preview {
    VStack(spacing: 24) {
        VoiceSampleSection(durationLabel: "0:00 / 0:08")
        VoiceSampleSection(durationLabel: "0:00 / 0:08", isOutdated: true)
        VoiceSampleSection(durationLabel: "0:00 / 0:08", isGenerating: true)
        VoiceSampleSection(durationLabel: "—", hasAudio: false)
    }
    .padding()
    .frame(width: 600)
}
