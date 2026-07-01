//
//  VoiceReferenceFeatureDemo.swift
//  tts_coach
//
//  Created by Shafa Tiara on 29/06/26.
//

import SwiftUI

/// Temporary glue just so we can click through the whole "Voice Reference
/// creation" feature in one preview/run — empty state -> modal -> done.
/// This is throwaway scaffolding: once the real navigation layer exists,
/// delete this file and wire `VoiceReferenceEmptyStateView` into the
/// actual Practice tab flow instead.
struct VoiceReferenceFeatureDemo: View {
    @State private var isPresentingCreateFlow = false

    var body: some View {
        VoiceReferenceEmptyStateView(onCreateVoiceReference: {
            isPresentingCreateFlow = true
        })
        .sheet(isPresented: $isPresentingCreateFlow) {
            CreateVoiceReferenceFlowView(
                onCancel: { isPresentingCreateFlow = false },
                onFinish: { _ in isPresentingCreateFlow = false }
            )
        }
    }
}

#Preview {
    VoiceReferenceFeatureDemo()
        .frame(width: 700, height: 700)
}
