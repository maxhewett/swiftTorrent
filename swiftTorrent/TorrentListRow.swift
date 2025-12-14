//
//  TorrentListRow.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct TorrentListRow: View {
    let t: TorrentRow
    @ObservedObject var engine: TorrentEngine

    var body: some View {
        HStack(spacing: 14) {

            posterView

            StatusIcon(state: t.state, isSeeding: t.isSeeding, isPaused: t.isPaused)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .lineLimit(1)

                if shouldShowProgressBar {
                    ProgressView(value: t.progress)
                        .animation(nil, value: t.progress)
                }

                if let statusLine = statusLineText {
                    HStack(spacing: 6) {
                        if showClockIcon { Image(systemName: "clock").foregroundStyle(.secondary) }
                        Text(statusLine)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            peersView
            speedView
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            TorrentWindOverlay(t: t)
                .allowsHitTesting(false)
        }
        .onAppear {
            engine.enrichIfNeeded(for: t)
        }
    }

    // MARK: - Trakt Display

    private var displayName: String {
        engine.mediaByTorrentID[t.id]?.title ?? t.name
    }

    private var posterURL: URL? {
        engine.mediaByTorrentID[t.id]?.posterURL
    }

    private var posterView: some View {
        Group {
            if let url = posterURL {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .empty:
                        posterPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        posterPlaceholder
                    @unknown default:
                        posterPlaceholder
                    }
                }
            } else {
                posterPlaceholder
            }
        }
        .frame(width: 34, height: 52) // tweak if you want bigger
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var posterPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Progress / Status

    private var shouldShowProgressBar: Bool {
        if t.isSeeding || t.state == 5 { return false }
        if t.progress >= 0.999 { return false }
        return true
    }

    private var percentString: String {
        let p = max(0, min(100, Int((t.progress * 100).rounded())))
        return "\(p)%"
    }

    private var showClockIcon: Bool {
        etaString() != nil
    }

    private var statusLineText: String? {
        if t.isPaused {
            return "Paused • \(percentString)"
        }

        if t.progress >= 0.999 {
            return "Download complete ✓"
        }

        if let eta = etaString() {
            return "\(eta) • \(percentString)"
        }

        return percentString
    }

    // MARK: - Subviews

    private var peersView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(t.seeds) \(plural(t.seeds, one: "seeder", many: "seeders"))")
            Text("\(t.peers) \(plural(t.peers, one: "peer", many: "peers"))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 120, alignment: .trailing)
    }

    private var speedView: some View {
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
        .frame(width: 130, alignment: .trailing)
    }

    // MARK: - ETA

    private func etaString() -> String? {
        guard !t.isPaused else { return nil }
        guard t.progress < 0.999 else { return nil }
        guard !t.isSeeding, t.state != 5 else { return nil }
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
        Image(systemName: iconName())
            .imageScale(.large)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .help(labelText())
            .frame(width: 26)
    }

    private func iconName() -> String {
        if isPaused { return "pause.circle.fill" }

        switch state {
        case 0: return "clock"
        case 1: return "checkmark.shield"
        case 2: return "magnifyingglass"
        case 3: return "arrow.down.circle.fill"
        case 4: return "checkmark.circle"
        case 5: return "leaf.circle.fill"
        case 6: return "square.stack.3d.up"
        case 7: return "bolt.badge.checkmark"
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
