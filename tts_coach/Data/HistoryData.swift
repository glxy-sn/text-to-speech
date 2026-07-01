//
//  HistoryData.swift
//  tts_coach
//
//  Created by Shafa Tiara on 01/07/26.
//

import SwiftUI
import Combine

/// Shared store for saved practice history entries — mirrors the
/// `VoiceLibraryStore` pattern so both `HistoryPageView` and
/// `PracticeFlowView` can read/write the same list without coupling
/// either to the other.
///
/// Hoisted as a `@StateObject` at `AppShellView` and injected via
/// `.environmentObject()` — same lifecycle as `VoiceLibraryStore`.
///
/// No `@MainActor` on the class itself for the same reason as
/// `VoiceLibraryStore`: combined with `ObservableObject`'s synthesized
/// conformance, it causes Swift 6 strict-concurrency errors. SwiftUI
/// already drives this on the main thread in practice.
final class HistoryStore: ObservableObject {
    @Published var entries: [PracticeHistoryEntry] = []

    /// Inserts a new entry at the top (newest first).
    func add(_ entry: PracticeHistoryEntry) {
        entries.insert(entry, at: 0)
    }

    /// Removes an entry — called after the user confirms deletion in
    /// `HistoryEntryCard`'s `confirmationDialog`.
    func delete(_ entry: PracticeHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
    }
}
