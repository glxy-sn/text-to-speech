//
//  Header.swift
//  tts_coach
//
//  Created by Shafa Tiara on 26/06/26.
//

import SwiftUI

/// Top header of the Results screen — title, score ring + message, and
/// action buttons. Matches mockup image 6, with 2 revisions:
/// - The old "Save" button is now "Download" (saving-to-History moved to
///   the Create Voice flow's naming step instead).
/// - "Download" sits below the "Good job!" message, not in the top row.
struct ResultsHeaderView: View {
    let score: Int
    var onShare: () -> Void = {}
    var onDownload: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice")
                    .font(.largeTitle.weight(.bold))
                Text("Great job! Review your pronunciation below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                ScoreRingView(score: score)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scoreLabel)
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Your pronunciation is clear. Keep practicing to sound even better.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 220, alignment: .leading)
                    }

                    Button(action: onDownload) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Download")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

        }
    }

    private var scoreLabel: String {
        switch score {
        case 80...: return "Good job!"
        case 60..<80: return "Nice try!"
        default: return "Keep practicing!"
        }
    }
}

#Preview {
    ResultsHeaderView(score: 82)
        .padding()
        .frame(width: 800)
}
