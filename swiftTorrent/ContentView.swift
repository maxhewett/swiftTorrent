//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TorrentEngine
    @EnvironmentObject private var magnetImport: MagnetImportCoordinator
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTorrentIDs: Set<String> = []
    @State private var showingAddSheet = false
    @State private var addSheetMagnet: String?
    @State private var errorText: String?
    @State private var confirmRemove = false
    @State private var torrentsToRemove: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }

            if visibleTorrents.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaPadding(.top, 8)
            } else {
                HSplitView {
                    sidebarPane
                        .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)

                    if let selectedTorrent {
                        detailPane {
                            TorrentInspectorView(torrent: selectedTorrent, engine: engine)
                        }
                    } else {
                        detailPane {
                            VStack(spacing: 12) {
                                Image(systemName: selectedTorrentIDs.count > 1 ? "cursorarrow.motionlines" : "cursorarrow")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(selectedTorrentIDs.count > 1
                                     ? "\(selectedTorrentIDs.count) torrents selected"
                                     : "Select a torrent")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Choose a torrent from the list to inspect files, category, and metadata.")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 240)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
                Button {
                    addSheetMagnet = nil
                    showingAddSheet = true
                } label: {
                    Label("Add Torrent", systemImage: "plus")
                }

                Button(role: .destructive) {
                    torrentsToRemove = selectedTorrentIDs
                    confirmRemove = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(selectedTorrentIDs.isEmpty)

                Button {
                    togglePauseResume()
                } label: {
                    Label(pauseResumeLabel, systemImage: pauseResumeSymbol)
                }
                .disabled(selectedTorrentIDs.isEmpty)
            }
        }
        .confirmationDialog(
            torrentsToRemove.count == 1 ? "Remove torrent?" : "Remove \(torrentsToRemove.count) torrents?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove (keep files)", role: .destructive) {
                removeSelected(deleteFiles: false)
            }

            Button("Remove + Delete files", role: .destructive) {
                removeSelected(deleteFiles: true)
            }

            Button("Cancel", role: .cancel) { torrentsToRemove = [] }
        } message: {
            Text("Choose whether to keep downloaded files or delete them too.")
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTorrentSheetView(initialMagnet: addSheetMagnet) { magnet, savePath, category, overrideQuery, overrideYear, overrideType in
                errorText = engine.addMagnet(
                    magnet,
                    savePath: savePath,
                    category: category,
                    overrideQuery: overrideQuery,
                    overrideYear: overrideYear,
                    overrideType: overrideType
                )
            }
            .id(addSheetMagnet ?? "__manual_add__")
            .presentationDetents([.medium])
            .onDisappear {
                magnetImport.clear()
            }
        }
        .onChange(of: magnetImport.pendingMagnet) { _, pendingMagnet in
            guard let pendingMagnet else { return }
            addSheetMagnet = pendingMagnet
            showingAddSheet = true
        }
        .frame(minWidth: 1050, minHeight: 560)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "film.stack")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text("No Torrents Yet")
                        .font(.title2.weight(.semibold))
                    Text("Add a magnet link to start downloading, then swiftTorrent will organise movies and shows here.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                Button {
                    addSheetMagnet = nil
                    showingAddSheet = true
                } label: {
                    Label("Add Torrent", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func torrentRow(_ t: TorrentRow) -> some View {
        TorrentListRow(t: t, engine: engine)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectionBackground(for: t))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture {
                selectedTorrentIDs = [t.id]
            }
            .contextMenu {
                let targets: Set<String> = selectedTorrentIDs.contains(t.id) ? selectedTorrentIDs : [t.id]
                let targetTorrents = engine.torrents.filter { targets.contains($0.id) }
                let allPaused = targetTorrents.allSatisfy { $0.isPaused }

                if allPaused {
                    Button { for id in targets { engine.resumeTorrent(id: id) } } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                } else {
                    Button { for id in targets { engine.pauseTorrent(id: id) } } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                }
                Divider()
                Button("Remove…", role: .destructive) {
                    torrentsToRemove = targets
                    confirmRemove = true
                }
            }
    }

    // MARK: - Selection

    private var selectedTorrent: TorrentRow? {
        guard selectedTorrentIDs.count == 1, let id = selectedTorrentIDs.first else { return nil }
        return visibleTorrents.first(where: { $0.id == id })
    }

    private var selectedTorrents: [TorrentRow] {
        visibleTorrents.filter { selectedTorrentIDs.contains($0.id) }
    }

    private var pauseResumeSymbol: String {
        selectedTorrents.allSatisfy { $0.isPaused } ? "play.fill" : "pause.fill"
    }

    private var pauseResumeLabel: String {
        selectedTorrents.allSatisfy { $0.isPaused } ? "Resume" : "Pause"
    }

    private func togglePauseResume() {
        let allPaused = selectedTorrents.allSatisfy { $0.isPaused }
        for t in selectedTorrents {
            if allPaused {
                engine.resumeTorrent(id: t.id)
            } else {
                engine.pauseTorrent(id: t.id)
            }
        }
    }

    private func removeSelected(deleteFiles: Bool) {
        for id in torrentsToRemove {
            engine.removeTorrent(id: id, deleteFiles: deleteFiles)
        }
        selectedTorrentIDs.subtract(torrentsToRemove)
        torrentsToRemove = []
    }

    // MARK: - Grouping

    private var grouped: (tv: [TorrentRow], movies: [TorrentRow], other: [TorrentRow]) {
        var tv: [TorrentRow] = []
        var movies: [TorrentRow] = []
        var other: [TorrentRow] = []

        for t in engine.torrents {
            let stable = stableKey(for: t)
            if settings.hiddenTorrentKeys.contains(stable) { continue }

            let c = settings.normalizedCategoryValue(t.category) ?? normalizeCategory(t.category)

            if c == "tv" {
                tv.append(t)
            } else if c == "movie" {
                movies.append(t)
            } else {
                other.append(t)
            }
        }

        return (
            tv.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            movies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            other.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    private var visibleTorrents: [TorrentRow] {
        engine.torrents.filter { !settings.hiddenTorrentKeys.contains(stableKey(for: $0)) }
    }

    private func stableKey(for torrent: TorrentRow) -> String {
        MagnetKeyExtractor.key(from: torrent.id) ?? torrent.id
    }

    private func normalizeCategory(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !grouped.tv.isEmpty {
                        sidebarSection(title: tvCategory.title, symbol: tvCategory.symbol, torrents: grouped.tv)
                    }

                    if !grouped.movies.isEmpty {
                        sidebarSection(title: movieCategory.title, symbol: movieCategory.symbol, torrents: grouped.movies)
                    }

                    if !grouped.other.isEmpty {
                        sidebarSection(title: "Other", symbol: "tray", torrents: grouped.other)
                    }
                }
                .padding(16)
            }
            .scrollClipDisabled()
        }
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.cyan.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(.ultraThinMaterial)
    }

    private func sidebarSection(title: String, symbol: String, torrents: [TorrentRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(torrents) { t in
                    torrentRow(t)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionBackground(for torrent: TorrentRow) -> some View {
        if selectedTorrentIDs.contains(torrent.id) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(.white.opacity(0.22)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                }
        }
    }

    private func detailPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(minWidth: 320, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.blue.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
            }
            .clipShape(Rectangle())
    }

    private var movieCategory: CategoryDefinition {
        settings.categoryDefinition(for: "movie") ?? CategoryDefinition(id: "movie", title: "Movies", symbol: "film", isLocked: true)
    }

    private var tvCategory: CategoryDefinition {
        settings.categoryDefinition(for: "tv") ?? CategoryDefinition(id: "tv", title: "TV", symbol: "tv", isLocked: true)
    }
}
