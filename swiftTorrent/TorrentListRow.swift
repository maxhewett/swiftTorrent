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

    private var isBoosted: Bool { engine.isBoosted(torrentID: t.id) }

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
                        .tint(isBoosted ? .orange : .accentColor)
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
            if canBoost {
                queueControls
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            TorrentWindOverlay(t: t, isBoosted: isBoosted)
                .allowsHitTesting(false)
        }
        .onAppear {
            engine.enrichIfNeeded(for: t)
        }
    }

    // MARK: - Trakt Display

    private var displayName: String {
        if let meta = engine.mediaByTorrentID[t.id] {
            var base = meta.title
            if let y = meta.year { base += " (\(y))" }
            if let suf = meta.displaySuffix, !suf.isEmpty { base += " • \(suf)" }
            return base
        }
        if engine.metadataLookupStateByID[t.id] == .failed {
            return t.name
        }
        return t.name
    }

    private var posterURL: URL? {
        if let local = engine.mediaByTorrentID[t.id]?.localPosterPath { return local }
        if let cached = PosterCache.load(for: t.id) { return cached }
        return engine.mediaByTorrentID[t.id]?.posterURL
    }

    private var posterView: some View {
        Group {
            if let url = posterURL {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .empty:
                        loadingPosterPlaceholder
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
                .id("row-poster-\(t.id)-\(url.absoluteString)")
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
        let category = (t.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbol: String
        switch category {
        case "tv":
            symbol = "tv"
        case "movie":
            symbol = "film"
        default:
            symbol = "tray"
        }
        return PosterFallbackView(symbol: symbol, cornerRadius: 6)
    }

    private var loadingPosterPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
            ProgressView()
                .controlSize(.small)
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
        let sizeProgress = "\(formatBytes(t.totalWantedDone))/\(formatBytes(t.totalWanted))"
        if engine.isQueued(torrentID: t.id) {
            return "Paused - Queued • \(percentString) • \(sizeProgress)"
        }

        if t.isPaused {
            return "Paused • \(percentString) • \(sizeProgress)"
        }

        if t.progress >= 0.999 {
            return "Download complete ✓ • \(sizeProgress)"
        }

        if let eta = etaString() {
            return "\(eta) • \(percentString) • \(sizeProgress)"
        }

        return "\(percentString) • \(sizeProgress)"
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

    private var queueControls: some View {
        Button {
            engine.toggleBoost(torrentID: t.id)
        } label: {
            BoostRocketIcon(isActive: isBoosted)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(isBoosted ? "Stop boosting this torrent" : "Temporarily boost this torrent")
        .frame(width: 26, alignment: .trailing)
    }

    private var canBoost: Bool {
        !t.isSeeding && t.state != 5 && t.progress < 0.999
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

    private func formatBytes(_ v: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, v), countStyle: .file)
    }

    private func plural(_ value: Int, one: String, many: String) -> String {
        value == 1 ? one : many
    }
}

private struct BoostRocketIcon: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                if isActive {
                    RocketExhaustFlame(phase: phase)
                        .mask(alignment: .bottom) {
                            Rectangle()
                                .frame(width: 10, height: 15)
                        }
                        .offset(y: 8.5)
                }

                RocketGlyphShape()
                    .fill(isActive ? Color.white : Color.secondary.opacity(0.42), style: FillStyle(eoFill: true))

            }
        }
        .accessibilityLabel(isActive ? "Boosted" : "Boost")
    }

}

private struct RocketExhaustFlame: View {
    let phase: TimeInterval

    var body: some View {
        ZStack {
            FlameShape()
                .fill(
                    LinearGradient(colors: [.yellow, .orange, .red.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 9, height: 15 + CGFloat(sin(phase * 18) * 2))

            FlameShape()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.95), .yellow, .orange.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 4, height: 9 + CGFloat(cos(phase * 22) * 1.5))
                .offset(y: -1)
        }
        .offset(
            x: CGFloat(sin(phase * 18) * 1.2),
            y: CGFloat((sin(phase * 11) + sin(phase * 17) * 0.55) * 1.35)
        )
        .blur(radius: 0.25)
    }
}

private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY * 0.72),
            control2: CGPoint(x: rect.minX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.midY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.maxY * 0.72)
        )
        path.closeSubpath()
        return path
    }
}

private struct RocketGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.50, y: h * 0.03))
        path.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.56),
            control1: CGPoint(x: w * 0.70, y: h * 0.12),
            control2: CGPoint(x: w * 0.76, y: h * 0.36)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.93, y: h * 0.89),
            control1: CGPoint(x: w * 0.82, y: h * 0.67),
            control2: CGPoint(x: w * 0.90, y: h * 0.80)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.67, y: h * 0.79),
            control: CGPoint(x: w * 0.79, y: h * 0.84)
        )
        path.addLine(to: CGPoint(x: w * 0.59, y: h * 0.91))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.41, y: h * 0.91),
            control: CGPoint(x: w * 0.50, y: h * 0.98)
        )
        path.addLine(to: CGPoint(x: w * 0.33, y: h * 0.79))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.07, y: h * 0.89),
            control: CGPoint(x: w * 0.21, y: h * 0.84)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.28, y: h * 0.56),
            control1: CGPoint(x: w * 0.10, y: h * 0.80),
            control2: CGPoint(x: w * 0.18, y: h * 0.67)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.04),
            control1: CGPoint(x: w * 0.24, y: h * 0.36),
            control2: CGPoint(x: w * 0.30, y: h * 0.12)
        )
        path.closeSubpath()

        path.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.24, width: w * 0.24, height: w * 0.24))
        path.closeSubpath()
        return path
    }
}

struct BoostedRowGlow: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.red.opacity(0.20), .orange.opacity(0.34), .yellow.opacity(0.16), .orange.opacity(0.28)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .blur(radius: 13)
                .padding(-5)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.red.opacity(0.28), .orange.opacity(0.70), .yellow.opacity(0.46), .orange.opacity(0.35)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    lineWidth: 1.2
                )
                .blur(radius: 1.4)
        }
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
