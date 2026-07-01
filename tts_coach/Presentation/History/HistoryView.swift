//
//  HistoryView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

//
//  HistoryView.swift
//  tts_coach
//
//  Created by Shafa Tiara on 28/06/26.
//

import SwiftUI

/// Full History page — backed by `HistoryViewModel` for UI state (search,
/// selection) and `HistoryStore` for the actual entries list.
///
/// Revision: entries now come from `historyStore` (environment) instead of
/// being seeded with sample data inside the ViewModel. The list updates
/// automatically whenever `PracticeFlowView` saves a completed session to
/// the store.
struct HistoryPageView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        if let entry = viewModel.selectedEntry {
            HistoryDetailView(entry: entry, onBack: { viewModel.clearSelection() })
        } else {
            listView
        }
    }

    private var listView: some View {
        let filtered = viewModel.filteredEntries(from: historyStore.entries)

        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)

            if historyStore.entries.isEmpty {
                HistoryEmptyStateView()
            } else if filtered.isEmpty {
                noSearchResultsView
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filtered) { entry in
                            HistoryEntryCard(
                                entry: entry,
                                onTap: { viewModel.select(entry) },
                                onDelete: { viewModel.delete(entry, from: historyStore) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(AppTheme.pageBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History").font(.largeTitle.weight(.bold))
                Text("Review your past pronunciation practice results.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search practice sessions...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .frame(maxWidth: 320)
        }
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No results for \"\(viewModel.searchText)\"")
                .font(.callout.weight(.medium))
            Text("Try a different search term.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    HistoryPageView()
        .environmentObject(HistoryStore())
        .frame(width: 700, height: 800)
}
