//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TorrentEngine

    @State private var selectedTorrentID: String?
    @State private var showingAddSheet = false
    @State private var errorText: String?
    @State private var confirmRemove = false

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }

            HSplitView {
                List(selection: $selectedTorrentID) {
                    Section {
                        ForEach(grouped.tv) { t in
                            TorrentListRow(t: t, engine: engine)
                                .tag(t.id)
                        }
                    } header: {
                        Label("TV", systemImage: "tv")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(grouped.movies) { t in
                            TorrentListRow(t: t, engine: engine)
                                .tag(t.id)
                        }
                    } header: {
                        Label("Movies", systemImage: "film")
                            .foregroundStyle(.secondary)
                    }

                    if !grouped.other.isEmpty {
                        Section {
                            ForEach(grouped.other) { t in
                                TorrentListRow(t: t, engine: engine)
                                    .tag(t.id)
                            }
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
                        Text("Select a torrent")
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
                    confirmRemove = true
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selectedTorrent == nil)

                Button {
                    togglePauseResume()
                } label: {
                    Label(pauseResumeLabel, systemImage: pauseResumeSymbol)
                }
                .disabled(selectedTorrent == nil)
            }
        }
        .confirmationDialog(
            "Remove torrent?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove (keep files)", role: .destructive) {
                removeSelected(deleteFiles: false)
            }

            Button("Remove + Delete files", role: .destructive) {
                removeSelected(deleteFiles: true)
            }

            Button("Cancel", role: .cancel) { }
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

    // MARK: - Selection

    private var selectedTorrent: TorrentRow? {
        guard let id = selectedTorrentID else { return nil }
        return engine.torrents.first(where: { $0.id == id })
    }

    private var pauseResumeSymbol: String {
        if let t = selectedTorrent, t.isPaused { return "play.fill" }
        return "pause.fill"
    }

    private var pauseResumeLabel: String {
        if let t = selectedTorrent, t.isPaused { return "Resume" }
        return "Pause"
    }

    private func togglePauseResume() {
        guard let t = selectedTorrent else { return }
        if t.isPaused {
            engine.resumeTorrent(id: t.id)
        } else {
            engine.pauseTorrent(id: t.id)
        }
    }

    private func removeSelected(deleteFiles: Bool) {
        guard let id = selectedTorrentID else { return }
        engine.removeTorrent(id: id, deleteFiles: deleteFiles)
        selectedTorrentID = nil
    }

    // MARK: - Grouping

    private var grouped: (tv: [TorrentRow], movies: [TorrentRow], other: [TorrentRow]) {
        var tv: [TorrentRow] = []
        var movies: [TorrentRow] = []
        var other: [TorrentRow] = []

        for t in engine.torrents {
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

    private func normalizeCategory(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
