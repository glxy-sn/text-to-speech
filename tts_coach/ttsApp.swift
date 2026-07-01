//
//  ttsApp.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Root shell — `NavigationSplitView` sidebar + detail for Practice / History / Voices.
///
/// Revision: hoisted `PronunciationScoringService` here alongside
/// `QwenTTSService` and `VoiceLibraryStore` / `HistoryStore` so the loaded
/// Wav2Vec2 CoreML model survives tab switches (same reasoning as the TTS
/// model). It's injected as an `.environmentObject` so any descendant view
/// that needs it can read it without passing it down manually.
struct AppShellView: View {
    @State private var selectedTab: AppTab?
    @State private var isPresentingCreateVoiceReference = false

    @StateObject private var voiceLibrary   = VoiceLibraryStore()
    @StateObject private var historyStore   = HistoryStore()
    @StateObject private var ttsService     = QwenTTSService()
    @StateObject private var scoringService = PronunciationScoringService()

    init(initialTab: AppTab? = .practice) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .navigationTitle(selectedTab?.rawValue ?? "Pronunciation Coach")
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .frame(minWidth: 900, minHeight: 600)
        .environmentObject(voiceLibrary)
        .environmentObject(historyStore)
        .environmentObject(ttsService)
        .environmentObject(scoringService)
        .sheet(isPresented: $isPresentingCreateVoiceReference) {
            CreateVoiceReferenceFlowView(
                onCancel: { isPresentingCreateVoiceReference = false },
                onFinish: { result in
                    isPresentingCreateVoiceReference = false
                    voiceLibrary.addVoice(
                        named: result.name,
                        referenceAudioURL: result.audioURL,
                        referenceTranscript: result.transcript
                    )
                }
            )
        }
    }

    // MARK: - Sub-views

    private var sidebar: some View {
        VStack(spacing: 0) {
            appHeader
            List(selection: $selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                }
            }
            .listStyle(.sidebar)
            .tint(AppTheme.accent)
        }
    }

    private var appHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundStyle(AppTheme.accent)
            Text("Pronunciation Coach").font(.headline)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .practice: practiceTabContent
        case .history:  HistoryPageView()
        case .voices:   VoicesPageView()
        case nil:
            Text("Select a menu item on the left").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var practiceTabContent: some View {
        if voiceLibrary.voices.isEmpty {
            VoiceReferenceEmptyStateView(onCreateVoiceReference: {
                isPresentingCreateVoiceReference = true
            })
        } else {
            PracticeFlowView()
        }
    }
}

#Preview { AppShellView() }
