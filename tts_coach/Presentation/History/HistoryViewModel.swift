//
//  HistoryViewModel.swift
//  tts_coach
//
//  Created by Shafa Tiara on 30/06/26.
//

import SwiftUI
import Combine

/// ViewModel for the History page. Owns only UI state:
/// - search text
/// - which entry is selected for the detail view
///
/// The entries list itself now lives in `HistoryStore` (injected via the
/// environment at `AppShellView` level) — same pattern as `VoiceLibraryStore`
/// / `VoicesPageViewModel`. The View reads `historyStore.entries` directly
/// and passes them into `filteredEntries(from:)` / `delete(_:from:)` as
/// plain parameters, keeping this VM free of environment-object coupling
/// and easy to test standalone.
///
/// Revision: removed `@Published var entries = .sampleHistory`. The sample
/// data is gone — entries now come from real completed practice sessions
/// saved by `PracticeFlowView` via `HistoryStore.add(_:)`.
final class HistoryViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedEntry: PracticeHistoryEntry?

    var isSearchEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Filters `entries` by the current `searchText`. Returns all entries
    /// when the search field is empty.
    func filteredEntries(from entries: [PracticeHistoryEntry]) -> [PracticeHistoryEntry] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.textPreview.localizedCaseInsensitiveContains(searchText)
        }
    }

    func select(_ entry: PracticeHistoryEntry) {
        selectedEntry = entry
    }

    func clearSelection() {
        selectedEntry = nil
    }

    /// Removes the entry from `store` and clears selection if needed.
    /// `HistoryEntryCard`'s `confirmationDialog` already confirmed with the
    /// user before this is called.
    func delete(_ entry: PracticeHistoryEntry, from store: HistoryStore) {
        store.delete(entry)
        if selectedEntry?.id == entry.id {
            selectedEntry = nil
        }
    }
}
