//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = TorrentEngine()

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
                            TorrentListRow(t: t).tag(t.id)
                        }
                    } header: {
                        Label("TV", systemImage: "tv").foregroundStyle(.secondary)
                    }

                    Section {
                        ForEach(grouped.movies) { t in
                            TorrentListRow(t: t).tag(t.id)
                        }
                    } header: {
                        Label("Movies", systemImage: "film").foregroundStyle(.secondary)
                    }

                    if !grouped.other.isEmpty {
                        Section {
                            ForEach(grouped.other) { t in
                                TorrentListRow(t: t).tag(t.id)
                            }
                        } header: {
                            Label("Other", systemImage: "tray").foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 650)

                if let selectedTorrent {
                    TorrentInspectorView(torrent: selectedTorrent, engine: engine)
                        .frame(minWidth: 320, idealWidth: 360)
                } else {
                    VStack {
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
            ToolbarItem(placement: .navigation) {
                Text("swiftTorrent").font(.headline)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Torrent", systemImage: "plus")
                }

                Divider()

                Button {
                    togglePauseResume()
                } label: {
                    Label(pauseResumeLabel, systemImage: pauseResumeSymbol)
                }
                .disabled(selectedTorrent == nil)

                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label("Remove", systemImage: "minus.circle")
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
                if let id = selectedTorrentID {
                    engine.removeTorrent(id: id, deleteFiles: false)
                    selectedTorrentID = nil
                }
            }

            Button("Remove + Delete files", role: .destructive) {
                if let id = selectedTorrentID {
                    engine.removeTorrent(id: id, deleteFiles: true)
                    selectedTorrentID = nil
                }
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

    private var selectedTorrent: TorrentRow? {
        guard let id = selectedTorrentID else { return nil }
        return engine.torrents.first(where: { $0.id == id })
    }

    private var pauseResumeSymbol: String {
        if let t = selectedTorrent, t.isPaused {
            return "play.fill"
        }
        return "pause.fill"
    }

    private var pauseResumeLabel: String {
        if let t = selectedTorrent, t.isPaused {
            return "Resume"
        }
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

// MARK: - Row

private struct TorrentListRow: View {
    let t: TorrentRow

    var body: some View {
        HStack(spacing: 14) {
            StatusIcon(state: t.state, isSeeding: t.isSeeding, isPaused: t.isPaused)

            VStack(alignment: .leading, spacing: 6) {
                Text(t.name)
                    .lineLimit(1)

                ProgressView(value: t.progress)
                    .animation(nil, value: t.progress)

                if let eta = etaString() {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text(eta)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(t.seeds) \(plural(t.seeds, one: "seeder", many: "seeders"))")
                Text("\(t.peers) \(plural(t.peers, one: "peer", many: "peers"))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 110, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                    Text(formatBps(t.downBps))
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                    Text(formatBps(t.upBps))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: ETA

    private func etaString() -> String? {
        // If paused, don’t show ETA (optional – feels nicer)
        guard !t.isPaused else { return nil }

        // Only show ETA while downloading and we have a rate
        guard t.progress < 0.999 else { return nil }
        guard t.downBps > 0 else { return nil }

        let remaining = max(Int64(0), t.totalWanted - t.totalWantedDone)
        guard remaining > 0 else { return nil }

        let seconds = Double(remaining) / Double(t.downBps)
        guard seconds.isFinite, seconds > 1 else { return nil }

        return "ETA \(formatDuration(seconds))"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60

        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    private func formatBps(_ bps: Int) -> String {
        let kb = Double(bps) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024.0)
    }

    private func plural(_ value: Int, one: String, many: String) -> String {
        value == 1 ? one : many
    }
}

// MARK: - Status Icon

private struct StatusIcon: View {
    let state: Int
    let isSeeding: Bool
    let isPaused: Bool

    var body: some View {
        let icon = iconName()
        let label = labelText()

        Image(systemName: icon)
            .imageScale(.large)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .help(label)
            .frame(width: 26)
    }

    private func iconName() -> String {
        // Paused should visually override everything else.
        if isPaused { return "pause.circle.fill" }

        switch state {
        case 0: return "clock"                    // queued
        case 1: return "checkmark.shield"         // checking
        case 2: return "magnifyingglass"          // metadata
        case 3: return "arrow.down.circle.fill"   // downloading
        case 4: return "checkmark.circle"         // finished
        case 5: return "leaf.circle.fill"         // seeding
        case 6: return "square.stack.3d.up"       // allocating
        case 7: return "bolt.badge.checkmark"     // checking fast
        default:
            return isSeeding ? "leaf.circle.fill" : "questionmark.circle"
        }
    }

    private func labelText() -> String {
        if isPaused { return "Paused" }

        switch state {
        case 0: return "Queued"
        case 1: return "Checking"
        case 2: return "Downloading metadata"
        case 3: return "Downloading"
        case 4: return "Finished"
        case 5: return "Seeding"
        case 6: return "Allocating"
        case 7: return "Checking (fast)"
        default: return "State \(state)"
        }
    }
}
