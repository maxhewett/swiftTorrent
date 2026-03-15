//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import AppKit

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
    @State private var showingRecentRail = false
    @State private var hostWindow: NSWindow?
    @State private var recentPanel = RecentDownloadsPanelController()
    @State private var resizeStartWidth: CGFloat?
    @AppStorage("swiftTorrent.ui.inspectorWidth") private var inspectorStoredWidth: Double = 340
    private let inspectorMinWidth: CGFloat = 320
    private let inspectorMaxWidth: CGFloat = 520

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
                HStack(spacing: 0) {
                    sidebarPane
                        .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)

                    dragHandle

                    detailPane {
                        if let selectedTorrent {
                            TorrentInspectorView(torrent: selectedTorrent, engine: engine)
                        } else {
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
        .background(WindowAccessor(window: $hostWindow))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar { mainToolbar }
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
        .onChange(of: showingRecentRail) { _, isShowing in
            syncRecentPanel(isShowing: isShowing, animated: true)
        }
        .onChange(of: hostWindow) { _, _ in
            syncRecentPanel(isShowing: showingRecentRail, animated: false)
        }
        .onDisappear {
            recentPanel.close(animated: false)
        }
        .frame(minWidth: 1050, minHeight: 560)
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
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

            Divider()

            Button {
                showingRecentRail.toggle()
            } label: {
                Label("Recent", systemImage: showingRecentRail ? "clock.badge.checkmark.fill" : "clock.badge.checkmark")
            }
            .help("Toggle recent downloads panel")
        }
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
            .frame(width: effectiveInspectorWidth)
            .frame(maxHeight: .infinity, alignment: .top)
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

    private var effectiveInspectorWidth: CGFloat {
        let value = CGFloat(inspectorStoredWidth)
        return min(inspectorMaxWidth, max(inspectorMinWidth, value))
    }

    private var dragHandle: some View {
        Color.clear
            .frame(width: 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = effectiveInspectorWidth
                        }
                        let base = resizeStartWidth ?? effectiveInspectorWidth
                        let proposed = base - value.translation.width
                        inspectorStoredWidth = Double(min(inspectorMaxWidth, max(inspectorMinWidth, proposed)).rounded())
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                    }
            )
    }

    private var movieCategory: CategoryDefinition {
        settings.categoryDefinition(for: "movie") ?? CategoryDefinition(id: "movie", title: "Movies", symbol: "film", isLocked: true)
    }

    private var tvCategory: CategoryDefinition {
        settings.categoryDefinition(for: "tv") ?? CategoryDefinition(id: "tv", title: "TV", symbol: "tv", isLocked: true)
    }

    private func syncRecentPanel(isShowing: Bool, animated: Bool) {
        guard let hostWindow else { return }
        if isShowing {
            recentPanel.show(parent: hostWindow, animated: animated)
        } else {
            recentPanel.close(animated: animated)
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

private final class RecentDownloadsPanelController {
    private var panel: NSPanel?
    private let width: CGFloat = 300

    func show(parent: NSWindow, animated: Bool) {
        let panel = ensurePanel()
        updateContent()
        let targetFrame = frame(for: parent)
        if panel.parent != parent {
            panel.orderOut(nil)
            parent.addChildWindow(panel, ordered: .below)
        }

        panel.setFrame(targetFrame, display: false)

        if !panel.isVisible {
            panel.alphaValue = animated ? 0 : 1
            panel.makeKeyAndOrderFront(nil)
            guard animated else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func close(animated: Bool) {
        guard let panel else { return }
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = InteractiveRecentPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 680),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.contentView = NSHostingView(rootView: RecentDownloadsPanelView())
        self.panel = panel
        return panel
    }

    private func updateContent() {
        guard let host = panel?.contentView as? NSHostingView<RecentDownloadsPanelView> else { return }
        host.rootView = RecentDownloadsPanelView()
    }

    private func frame(for parent: NSWindow) -> NSRect {
        let parentFrame = parent.frame
        let height = max(440, parentFrame.height - 22)
        let y = parentFrame.minY + ((parentFrame.height - height) / 2)
        let x = parentFrame.maxX - 16
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class InteractiveRecentPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

private struct RecentDownloadsPanelView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let relativeDateTimeFormatter = RelativeDateTimeFormatter()
    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 22, topTrailing: 22),
            style: .continuous
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Downloads", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.headline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if settings.recentDownloads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No recent completions")
                        .font(.subheadline.weight(.semibold))
                    Text("Completed torrents will appear here with posters and timings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 200)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(settings.recentDownloads.prefix(60)), id: \.id) { item in
                            recentDownloadRow(item)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        settings.removeRecentDownload(id: item.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.cyan.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
            .opacity(0.2)
        )
        .clipShape(panelShape)
        .overlay {
            panelShape
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .glassEffect(.regular, in: panelShape)
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 10)
    }

    private func recentDownloadRow(_ item: RecentDownloadItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            recentPosterView(item)
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title + (item.year.map { " (\($0))" } ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(item.outcome)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.typeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(durationLabel(item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(relativeDateTimeFormatter.localizedString(for: item.completedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func recentPosterView(_ item: RecentDownloadItem) -> some View {
        RecentPosterThumbnail(localPath: item.posterLocalPath, remoteURLString: item.posterRemoteURL)
    }

    private var posterFallback: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            Image(systemName: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func durationLabel(_ item: RecentDownloadItem) -> String {
        guard let seconds = item.durationSeconds else { return "Tracking time unavailable" }
        if seconds < 60 {
            return "Completed in \(Int(seconds))s"
        }
        if seconds < 3600 {
            return "Completed in \(Int(seconds / 60))m"
        }
        return String(format: "Completed in %.1fh", seconds / 3600)
    }
}

private struct RecentPosterThumbnail: View {
    let localPath: String?
    let remoteURLString: String?
    @State private var image: NSImage?
    @State private var isLoading = false

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.white.opacity(0.08))
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: cacheKey) {
            await load()
        }
    }

    private var cacheKey: String {
        if let localPath {
            return "file:\(localPath)"
        }
        if let remoteURLString {
            return "url:\(remoteURLString)"
        }
        return "none"
    }

    @MainActor
    private func load() async {
        guard cacheKey != "none" else {
            image = nil
            return
        }
        if let cached = Self.cache.object(forKey: cacheKey as NSString) {
            image = cached
            return
        }

        isLoading = true
        defer { isLoading = false }

        if let localPath, let localImage = NSImage(contentsOfFile: localPath) {
            Self.cache.setObject(localImage, forKey: cacheKey as NSString)
            image = localImage
            return
        }

        guard let remoteURLString, let remoteURL = URL(string: remoteURLString) else {
            image = nil
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            if let loadedImage = NSImage(data: data) {
                Self.cache.setObject(loadedImage, forKey: cacheKey as NSString)
                image = loadedImage
            } else {
                image = nil
            }
        } catch {
            image = nil
        }
    }
}
