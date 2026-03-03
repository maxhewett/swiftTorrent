//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TorrentEngine
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTorrentIDs: Set<String> = []
    @State private var showingAddSheet = false
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
            }

            HSplitView {
                List(selection: $selectedTorrentIDs) {
                    Section {
                        ForEach(grouped.tv) { t in torrentRow(t) }
                    } header: {
                        Label("TV", systemImage: "tv")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(grouped.movies) { t in torrentRow(t) }
                    } header: {
                        Label("Movies", systemImage: "film")
                            .foregroundStyle(.secondary)
                    }

                    if !grouped.other.isEmpty {
                        Section {
                            ForEach(grouped.other) { t in torrentRow(t) }
                        } header: {
                            Label("Other", systemImage: "tray")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 650)

                if let selectedTorrent {
                    TorrentInspectorView(torrent: selectedTorrent, engine: engine)
                        .frame(minWidth: 320, idealWidth: 360)
                } else {
                    VStack(spacing: 10) {
                        Text(selectedTorrentIDs.count > 1
                             ? "\(selectedTorrentIDs.count) torrents selected"
                             : "Select a torrent")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .frame(minWidth: 320, idealWidth: 360)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
                Button {
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
            AddTorrentSheetView { magnet, savePath, category in
                errorText = engine.addMagnet(magnet, savePath: savePath, category: category)
            }
            .presentationDetents([.medium])
        }
        .frame(minWidth: 1050, minHeight: 560)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func torrentRow(_ t: TorrentRow) -> some View {
        TorrentListRow(t: t, engine: engine)
            .tag(t.id)
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

            let c = normalizeCategory(t.category)

            if c == "tv" || c == "sonarr" || c.contains("tv") {
                tv.append(t)
            } else if c == "movie" || c == "movies" || c == "radarr" || c.contains("movie") {
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
}
