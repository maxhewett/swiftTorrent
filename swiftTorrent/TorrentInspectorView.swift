//
//  TorrentInspectorView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct TorrentInspectorView: View {
    let torrent: TorrentRow
    @ObservedObject var engine: TorrentEngine

    @State private var categoryText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(torrent.name)
                .font(.headline)
                .lineLimit(2)

            // Media block
            if let meta = engine.mediaByTorrentID[torrent.id] {
                MediaInfoBlock(meta: meta, torrentID: torrent.id)
                    .padding(.top, 4)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching details…")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            HStack(spacing: 8) {
                Text(stateLabel(torrent.state))
                    .foregroundStyle(.secondary)
                Text("• \(torrent.peers) Peers • \(torrent.seeds) Seeders")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: torrent.progress)
                .animation(nil, value: torrent.progress)

            HStack {
                Text("↓ \(formatBps(torrent.downBps))")
                Spacer()
                Text("↑ \(formatBps(torrent.upBps))")
            }
            .foregroundStyle(.secondary)

            Divider()

            Text("Category")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                engine.cleanupNow(torrentID: torrent.id)
            } label: {
                Label("Clean Up Now", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .disabled(engine.mediaByTorrentID[torrent.id] == nil)

            HStack {
                TextField("e.g. tv-sonarr / movies-radarr", text: $categoryText)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    let trimmed = categoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                    engine.setCategory(trimmed.isEmpty ? nil : trimmed, for: torrent.id)
                }
            }

            Button(role: .destructive) {
                engine.setCategory(nil, for: torrent.id)
                categoryText = ""
            } label: {
                Text("Clear Category")
            }
            .buttonStyle(.bordered)

            Spacer()

            GroupBox("Files") {
                let files = engine.filesByTorrentID[torrent.id] ?? []

                if files.isEmpty {
                    Text("No file list available yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(files) { f in
                        let pathURL = URL(fileURLWithPath: f.path)
                        let filename = pathURL.lastPathComponent
                        let parentPath = pathURL.deletingLastPathComponent().path
                        let showParent = parentPath != "." && parentPath != "/"

                        VStack(alignment: .leading, spacing: 6) {
                            Text(filename)
                                .font(.body)
                                .lineLimit(1)

                            if showParent {
                                Text(parentPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            if f.progress >= 0.999 {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Download complete")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            } else {
                                ProgressView(value: f.progress)
                                    .animation(nil, value: f.progress)

                                Text("\(formatBytes(f.done)) / \(formatBytes(f.size))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(minHeight: 180)
                }
            }
            .onAppear {
                engine.refreshFiles(for: torrent.id)
                engine.enrichIfNeeded(for: torrent)
            }
            .onChange(of: torrent.id) { _, newID in
                engine.refreshFiles(for: newID)
                if let t = engine.torrents.first(where: { $0.id == newID }) {
                    engine.enrichIfNeeded(for: t)
                }
            }
        }
        .padding()
        .onAppear {
            categoryText = torrent.category ?? ""
        }
        .onChange(of: torrent.category) { _, newValue in
            if (newValue ?? "") != categoryText {
                categoryText = newValue ?? ""
            }
        }
    }

    private func formatBps(_ bps: Int) -> String {
        let kb = Double(bps) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024.0)
    }

    private func formatBytes(_ v: Int64) -> String {
        let b = Double(v)
        let kb = b / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(v) B"
    }

    private func stateLabel(_ s: Int) -> String {
        switch s {
        case 0: return "Queued"
        case 1: return "Checking"
        case 2: return "DL metadata"
        case 3: return "Downloading"
        case 4: return "Finished"
        case 5: return "Seeding"
        case 6: return "Allocating"
        case 7: return "Checking fast"
        default: return "State \(s)"
        }
    }
}

private struct MediaInfoBlock: View {
    let meta: MediaMetadata
    let torrentID: String

    // ✅ Use cached poster if present, otherwise remote URL
    private var resolvedPosterURL: URL? {
        PosterCache.load(for: torrentID) ?? meta.posterURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            poster

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(meta.title)
                        .font(.headline)
                        .lineLimit(2)

                    if let year = meta.year {
                        Text("(\(String(year)))")
                            .foregroundStyle(.secondary)
                    }
                }

                if let suffix = meta.displaySuffix, !suffix.isEmpty {
                    Text(suffix)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let overview = meta.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var poster: some View {
        Group {
            if let url = resolvedPosterURL {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 70, height: 105)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}
