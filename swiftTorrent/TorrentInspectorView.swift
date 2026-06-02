//
//  TorrentInspectorView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TorrentInspectorView: View {
    let torrent: TorrentRow
    @ObservedObject var engine: TorrentEngine
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedCategory = ""
    @State private var showingMatchSheet = false
    @State private var showingFileBrowser = false
    @State private var showingDetailsSheet = false
    @State private var selectedTab: InspectorTab = .status
    @State private var cleanupDestinationOverride: URL?
    @State private var overrideQuery: String = ""
    @State private var overrideYearText: String = ""
    @State private var overrideType: OverrideType = .auto

    private enum OverrideType: String, CaseIterable, Identifiable {
        case auto
        case movie
        case show

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case status, files, category, cleanup

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .status: return "chart.bar"
            case .files: return "doc.on.doc"
            case .category: return "tag"
            case .cleanup: return "arrow.trianglehead.branch"
            }
        }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()
            inspectorTabs
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectedTabContent
                }
                .padding()
            }

            if hasPinnedActions {
                Divider()
                pinnedActions
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .onAppear {
            selectedCategory = settings.normalizedCategoryValue(torrent.category) ?? ""
            loadOverrideFields()
            engine.refreshFiles(for: torrent.id)
            engine.enrichIfNeeded(for: torrent)
        }
        .onChange(of: torrent.category) { _, newValue in
            selectedCategory = settings.normalizedCategoryValue(newValue) ?? ""
        }
        .onChange(of: torrent.id) { _, newID in
            selectedCategory = settings.normalizedCategoryValue(torrent.category) ?? ""
            loadOverrideFields()
            engine.refreshFiles(for: newID)
            if let t = engine.torrents.first(where: { $0.id == newID }) {
                engine.enrichIfNeeded(for: t)
            }
        }
        .sheet(isPresented: $showingMatchSheet) {
            matchSheet
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingFileBrowser) {
            TorrentFileBrowserSheet(torrent: torrent, engine: engine)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingDetailsSheet) {
            if let meta = engine.mediaByTorrentID[torrent.id] {
                MediaDetailsSheet(meta: meta, torrentID: torrent.id, torrentName: torrent.name)
                    .presentationBackground(.clear)
            }
        }
        .onChange(of: showingMatchSheet) { _, isShowing in
            guard isShowing else { return }
            engine.fetchMetadataCandidates(
                for: torrent.id,
                query: overrideQuery,
                year: Int(overrideYearText),
                preferredType: selectedOverrideType
            )
        }
    }

    private var hasPinnedActions: Bool {
        selectedTab == .files || selectedTab == .cleanup
    }

    @ViewBuilder
    private var pinnedActions: some View {
        switch selectedTab {
        case .files:
            Button {
                showingFileBrowser = true
            } label: {
                Label("Inspect All \(files.count) Files…", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(files.isEmpty)
        case .cleanup:
            HStack {
                Button("Organize Now") {
                    engine.organizeNow(torrentID: torrent.id, destinationOverride: cleanupDestinationOverride)
                }
                .buttonStyle(.borderedProminent)

                Button("Override Destination…") {
                    chooseCleanupDestination()
                }
                .buttonStyle(.bordered)

                if cleanupDestinationOverride != nil {
                    Button("Reset") { cleanupDestinationOverride = nil }
                        .buttonStyle(.borderless)
                }
            }
        default:
            EmptyView()
        }
    }

    private var inspectorTabs: some View {
        HStack(spacing: 4) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .background(selectedTab == tab ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .help(tab.label)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .status:
            statsSection
        case .files:
            filesSection
        case .category:
            categorySection
        case .cleanup:
            cleanupSection
        }
    }

    private var header: some View {
        Group {
            if let meta = engine.mediaByTorrentID[torrent.id] {
                MediaInfoBlock(
                    meta: meta,
                    torrentID: torrent.id,
                    torrentName: torrent.name,
                    totalWanted: torrent.totalWanted,
                    fileCount: files.count,
                    skippedFileCount: skippedFilesCount,
                    sourceLabel: engine.sourceLabel(for: torrent.id),
                    onFixMatch: { showingMatchSheet = true },
                    onShowDetails: { showingDetailsSheet = true }
                )
            } else if engine.metadataLookupStateByID[torrent.id] == .failed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No match found", systemImage: "exclamationmark.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(torrent.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("Use Fix Match to adjust the search title, year, or type.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Retry") {
                            engine.refreshMetadata(for: torrent)
                        }
                        .buttonStyle(.bordered)

                        Button("Fix Match") {
                            showingMatchSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching details…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let duplicateWarning {
                Label(duplicateWarning, systemImage: "square.on.square")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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

            TransferSpeedGraph(samples: engine.transferSpeedSamplesByID[torrent.id] ?? [])
                .frame(height: 120)
        }
    }

    private var duplicateWarning: String? {
        guard let selected = engine.mediaByTorrentID[torrent.id] else { return nil }
        let duplicates = engine.mediaByTorrentID.filter { id, candidate in
            guard id != torrent.id, candidate.type == selected.type else { return false }
            if let traktID = selected.traktID, candidate.traktID == traktID { return true }
            if let tmdbID = selected.tmdbID, candidate.tmdbID == tmdbID { return true }
            if let tvdbID = selected.tvdbID, candidate.tvdbID == tvdbID { return true }
            if let imdbID = selected.imdbID, candidate.imdbID == imdbID { return true }
            return candidate.title.localizedCaseInsensitiveCompare(selected.title) == .orderedSame && candidate.year == selected.year
        }
        guard !duplicates.isEmpty else { return nil }
        return "Possible duplicate: this media item is already present."
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Category", systemImage: "tag")
                .font(.headline)

            Picker("Category", selection: $selectedCategory) {
                Text("None").tag("")
                ForEach(categoryOptions) { category in
                    Label(category.title, systemImage: category.symbol).tag(category.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedCategory) { _, newValue in
                engine.setCategory(newValue.isEmpty ? nil : newValue, for: torrent.id)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(selectedCategoryDefinition?.title ?? "Uncategorized", systemImage: selectedCategoryDefinition?.symbol ?? "tray")
                    .font(.subheadline.weight(.medium))

                Label {
                    Text(settings.preferredSavePath(for: selectedCategory))
                        .font(.caption.monospaced())
                        .lineLimit(3)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }

                Label {
                    Text(categoryExclusionSummary)
                        .font(.caption)
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var selectedCategoryDefinition: CategoryDefinition? {
        settings.categoryDefinition(for: selectedCategory)
    }

    private var categoryExclusionSummary: String {
        let count = settings.fileExclusionRules.filter { rule in
            rule.appliesToAllCategories || rule.categoryIDs.contains(selectedCategory)
        }.count
        return count == 1 ? "1 file exclusion rule applies" : "\(count) file exclusion rules apply"
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Files", systemImage: "doc.on.doc")
                    .font(.headline)
                Spacer()
                if !files.isEmpty {
                    Text(fileSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if files.isEmpty {
                    Text("No file list available yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(sortedFiles) { file in
                                fileRow(file)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cleanup Preview", systemImage: "arrow.trianglehead.branch")
                .font(.headline)

            if let plan = engine.cleanupPreview(torrentID: torrent.id, destinationOverride: cleanupDestinationOverride) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.destinationFolder.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                Divider()

                ForEach(plan.files.prefix(8)) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.source.lastPathComponent)
                            .font(.caption.weight(.medium))
                        Text(file.destination.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if plan.files.count > 8 {
                    Text("\(plan.files.count - 8) more files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Cleanup preview will appear once metadata, files, and destination folders are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
    }

    private func chooseCleanupDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Destination"
        if panel.runModal() == .OK {
            cleanupDestinationOverride = panel.url
        }
    }

    private var files: [TorrentFile] {
        engine.filesByTorrentID[torrent.id] ?? []
    }

    private var skippedFilesCount: Int {
        files.filter(\.isSkipped).count
    }

    private var sortedFiles: [TorrentFile] {
        files.sorted {
            if $0.isPrioritized != $1.isPrioritized {
                return $0.isPrioritized
            }
            return $0.id < $1.id
        }
    }

    private var fileSummary: String {
        skippedFilesCount > 0 ? "\(files.count) files • \(skippedFilesCount) skipped" : "\(files.count) files"
    }

    private var categoryOptions: [CategoryDefinition] {
        let merged = settings.categoryDefinitionsForUI + extraCategoryDefinition
        var seen: Set<String> = []
        return merged.filter { seen.insert($0.id).inserted }
    }

    private var extraCategoryDefinition: [CategoryDefinition] {
        guard let normalized = settings.normalizedCategoryValue(torrent.category) else { return [] }
        guard settings.categoryDefinition(for: normalized) == nil else { return [] }
        return [CategoryDefinition(id: normalized, title: normalized.capitalized, symbol: "tag")]
    }

    private func fileRow(_ file: TorrentFile) -> some View {
        let filename = URL(fileURLWithPath: file.path).lastPathComponent

        return HStack(alignment: .top, spacing: 8) {
            FileTypeIconView(path: file.path, size: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(filename)
                        .font(.subheadline)
                        .lineLimit(1)

                    if file.isPrioritized {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    if file.isSkipped {
                        Text("Skipped")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                if file.isSkipped {
                    Text("\(formatBytes(file.size)) excluded from download")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if file.progress >= 0.999 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("Download complete")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                } else {
                    ProgressView(value: file.progress)
                        .animation(nil, value: file.progress)
                        .controlSize(.small)

                    Text("\(formatBytes(file.done)) / \(formatBytes(file.size))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Button {
                    engine.setFilePrioritized(!file.isPrioritized, torrentID: torrent.id, fileID: file.id)
                } label: {
                    Image(systemName: file.isPrioritized ? "star.fill" : "star")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(file.isPrioritized ? .yellow : .secondary)
                .disabled(file.isSkipped)
                .help(file.isSkipped ? "Include this file before prioritizing it" : (file.isPrioritized ? "Use normal file priority" : "Prioritize this file"))

                Button {
                    engine.setFileWanted(file.isSkipped, torrentID: torrent.id, fileID: file.id)
                } label: {
                    Image(systemName: file.isSkipped ? "arrow.down.circle" : "slash.circle")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help(file.isSkipped ? "Include this file in the download" : "Skip this file")
            }
        }
    }

    private var overrideEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search Override")
                    .font(.headline)
                Text("Adjust the title, year, or media type when Trakt picks the wrong item or returns nothing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Search title", text: $overrideQuery)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    TextField("Year", text: $overrideYearText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    Picker("Type", selection: $overrideType) {
                        ForEach(OverrideType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Apply") {
                        let selectedType: MediaMetadata.MediaType?
                        switch overrideType {
                        case .auto:
                            selectedType = nil
                        case .movie:
                            selectedType = .movie
                        case .show:
                            selectedType = .show
                        }
                        engine.setMetadataOverride(
                            for: torrent.id,
                            query: overrideQuery,
                            year: Int(overrideYearText),
                            type: selectedType
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Search") {
                        engine.fetchMetadataCandidates(
                            for: torrent.id,
                            query: overrideQuery,
                            year: Int(overrideYearText),
                            preferredType: selectedOverrideType
                        )
                    }
                    .buttonStyle(.bordered)

                    Button("Parsed") {
                        let parsed = TorrentNameParser.parse(torrent.name)
                        overrideQuery = parsed.query
                        overrideYearText = parsed.year.map(String.init) ?? ""
                    }
                    .buttonStyle(.bordered)

                    Button("Clear", role: .destructive) {
                        overrideQuery = ""
                        overrideYearText = ""
                        overrideType = .auto
                        engine.setMetadataOverride(for: torrent.id, query: nil, year: nil, type: nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )

            let candidates = engine.metadataCandidatesByID[torrent.id] ?? []
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Candidates")
                        .font(.headline)
                    Text("Pick a result to replace the current match immediately.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(candidates) { candidate in
                        Button {
                            overrideQuery = candidate.title
                            overrideYearText = candidate.year.map(String.init) ?? ""
                            overrideType = candidate.type == .movie ? .movie : .show
                            engine.setMetadataOverride(
                                for: torrent.id,
                                query: candidate.title,
                                year: candidate.year,
                                type: candidate.type
                            )
                            showingMatchSheet = false
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CandidatePosterView(candidate: candidate)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.title + (candidate.year.map { " (\($0))" } ?? ""))
                                        .foregroundStyle(.primary)
                                    Text(candidate.type == .movie ? "Movie" : "Show")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let overview = candidate.overview, !overview.isEmpty {
                                        Text(overview)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text("\(candidate.score)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
            } else if engine.metadataLookupStateByID[torrent.id] == .failed {
                Text("No Trakt candidates found for the current title/year.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.08))
                    )
            }
        }
    }

    private var matchSheet: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fix Match")
                            .font(.title3.weight(.semibold))
                        Text("Override the parsed search and pick the correct Trakt result.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") {
                        showingMatchSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 18)

                ScrollView {
                    overrideEditor
                }
            }
            .padding(22)
            .frame(minWidth: 560, idealWidth: 620, minHeight: 480, maxHeight: 760, alignment: .top)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
            .padding(18)
        }
    }

    private var selectedOverrideType: MediaMetadata.MediaType? {
        switch overrideType {
        case .auto:
            return nil
        case .movie:
            return .movie
        case .show:
            return .show
        }
    }

    private func loadOverrideFields() {
        let parsed = TorrentNameParser.parse(torrent.name)
        let saved = engine.currentMetadataOverride(for: torrent.id)
        overrideQuery = saved.query ?? parsed.query
        overrideYearText = (saved.year ?? parsed.year).map(String.init) ?? ""
        switch saved.type {
        case .movie:
            overrideType = .movie
        case .show:
            overrideType = .show
        case nil:
            overrideType = .auto
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

private struct TorrentFileBrowserSheet: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case included
        case skipped
        case video
        case audio
        case subtitles
        case other

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    let torrent: TorrentRow
    @ObservedObject var engine: TorrentEngine
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var isSelecting = false
    @State private var selectedFileIDs: Set<Int> = []

    private var files: [TorrentFile] {
        engine.filesByTorrentID[torrent.id] ?? []
    }

    private var visibleFiles: [TorrentFile] {
        files.sorted {
            if $0.isPrioritized != $1.isPrioritized {
                return $0.isPrioritized
            }
            return $0.id < $1.id
        }
        .filter { file in
            let matchesSearch = searchText.isEmpty || file.path.localizedCaseInsensitiveContains(searchText)
            guard matchesSearch else { return false }
            switch filter {
            case .all: return true
            case .included: return !file.isSkipped
            case .skipped: return file.isSkipped
            case .video: return fileKind(file) == .video
            case .audio: return fileKind(file) == .audio
            case .subtitles: return fileKind(file) == .subtitles
            case .other: return fileKind(file) == .other
            }
        }
    }

    private var skippedCount: Int { files.filter(\.isSkipped).count }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()

                toolbar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                Divider()

                if visibleFiles.isEmpty {
                    ContentUnavailableView("No Matching Files", systemImage: "doc.text.magnifyingglass", description: Text("Adjust the search or file filter."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleFiles) { file in
                                fileBrowserRow(file)
                                Divider()
                                    .padding(.leading, 62)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
            .frame(minWidth: 780, idealWidth: 900, minHeight: 560, idealHeight: 680)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        }
        .onAppear {
            engine.refreshFiles(for: torrent.id)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Files")
                    .font(.title2.weight(.semibold))
                Text(torrent.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(fileSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isSelecting ? "Done Selecting" : "Select") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedFileIDs.removeAll()
                    }
                }
            }
            .buttonStyle(.bordered)

            if isSelecting {
                Button(allFilesSelected ? "Deselect All" : "Select All") {
                    toggleAllFilesSelection()
                }
                .buttonStyle(.bordered)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search files", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 300)

            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Spacer()

            if isSelecting {
                Text(selectedFileIDs.isEmpty ? "No files selected" : "\(selectedFileIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(allVisibleSelected ? "Deselect Visible" : "Select Visible") {
                    toggleAllVisibleSelection()
                }
                .buttonStyle(.borderless)

                Menu("Bulk Actions") {
                    Button("Include Selected") { setSelectedFilesWanted(true) }
                    Button("Skip Selected") { setSelectedFilesWanted(false) }
                    Divider()
                    Button("Prioritize Selected") { setSelectedFilesPrioritized(true) }
                    Button("Use Normal Priority") { setSelectedFilesPrioritized(false) }
                }
                .menuStyle(.borderlessButton)
                .disabled(selectedFileIDs.isEmpty)
            } else {
                Menu("Quick Actions") {
                    Button("Include Media Only") {
                        let mediaIDs = files.filter { fileKind($0) != .other }.map(\.id)
                        let otherIDs = files.filter { fileKind($0) == .other }.map(\.id)
                        engine.setFilesWanted(false, torrentID: torrent.id, fileIDs: otherIDs)
                        engine.setFilesWanted(true, torrentID: torrent.id, fileIDs: mediaIDs)
                    }
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private func fileBrowserRow(_ file: TorrentFile) -> some View {
        let pathURL = URL(fileURLWithPath: file.path)
        let filename = pathURL.lastPathComponent
        let parent = pathURL.deletingLastPathComponent().path

        return HStack(spacing: 12) {
            if isSelecting {
                Button {
                    toggleSelection(for: file.id)
                } label: {
                    Image(systemName: selectedFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedFileIDs.contains(file.id) ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            FileTypeIconView(path: file.path, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(filename)
                    .lineLimit(1)
                if parent != "." && parent != "/" {
                    Text(parent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ProgressView(value: file.progress)
                    .animation(nil, value: file.progress)
            }

            Spacer(minLength: 14)

            VStack(alignment: .trailing, spacing: 4) {
                Text(file.isSkipped ? "Skipped" : "\(formatBytes(file.done)) / \(formatBytes(file.size))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(file.isSkipped ? .secondary : .primary)
                if file.isPrioritized {
                    Text("Prioritized")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.yellow)
                }
            }

            if !isSelecting {
                HStack(spacing: 10) {
                    Button {
                        engine.setFilePrioritized(!file.isPrioritized, torrentID: torrent.id, fileID: file.id)
                    } label: {
                        Image(systemName: file.isPrioritized ? "star.fill" : "star")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(file.isPrioritized ? .yellow : .secondary)
                    .disabled(file.isSkipped)
                    .help(file.isSkipped ? "Include this file before prioritizing it" : (file.isPrioritized ? "Use normal file priority" : "Prioritize this file"))

                    Button {
                        engine.setFileWanted(file.isSkipped, torrentID: torrent.id, fileID: file.id)
                    } label: {
                        Image(systemName: file.isSkipped ? "arrow.down.circle" : "slash.circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .help(file.isSkipped ? "Include this file in the download" : "Skip this file")
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var fileSummary: String {
        skippedCount > 0
            ? "\(files.count) files • \(skippedCount) skipped"
            : "\(files.count) files"
    }

    private var allVisibleSelected: Bool {
        !visibleFiles.isEmpty && visibleFiles.allSatisfy { selectedFileIDs.contains($0.id) }
    }

    private var allFilesSelected: Bool {
        !files.isEmpty && files.allSatisfy { selectedFileIDs.contains($0.id) }
    }

    private func toggleSelection(for fileID: Int) {
        if selectedFileIDs.contains(fileID) {
            selectedFileIDs.remove(fileID)
        } else {
            selectedFileIDs.insert(fileID)
        }
    }

    private func toggleAllVisibleSelection() {
        if allVisibleSelected {
            selectedFileIDs.subtract(visibleFiles.map(\.id))
        } else {
            selectedFileIDs.formUnion(visibleFiles.map(\.id))
        }
    }

    private func toggleAllFilesSelection() {
        if allFilesSelected {
            selectedFileIDs.removeAll()
        } else {
            selectedFileIDs = Set(files.map(\.id))
        }
    }

    private func setSelectedFilesWanted(_ wanted: Bool) {
        engine.setFilesWanted(wanted, torrentID: torrent.id, fileIDs: Array(selectedFileIDs))
    }

    private func setSelectedFilesPrioritized(_ prioritized: Bool) {
        engine.setFilesPrioritized(prioritized, torrentID: torrent.id, fileIDs: Array(selectedFileIDs))
    }

    private enum FileKind {
        case video
        case audio
        case subtitles
        case other
    }

    private func fileKind(_ file: TorrentFile) -> FileKind {
        let ext = URL(fileURLWithPath: file.path).pathExtension.lowercased()
        if ["3gp", "3g2", "asf", "avi", "divx", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "ogm", "ogv", "ts", "vob", "webm", "wmv"].contains(ext) {
            return .video
        }
        if ["flac", "m4a", "m4b", "mka", "mp3", "oga", "ogg", "opus", "wav", "wma"].contains(ext) {
            return .audio
        }
        if ["ass", "idx", "smi", "srt", "ssa", "sub", "sup", "vtt"].contains(ext) {
            return .subtitles
        }
        return .other
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
}

private struct TransferSpeedGraph: View {
    let samples: [TransferSpeedSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Transfer Speed", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Active session")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary.opacity(0.035))

                    graphLine(in: proxy.size, value: \.downBps)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                    graphLine(in: proxy.size, value: \.upBps)
                        .stroke(.green.opacity(0.88), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }

            HStack(spacing: 12) {
                Label("Download", systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label("Upload", systemImage: "arrow.up")
                    .foregroundStyle(.green)
            }
            .font(.caption2)
        }
    }

    private func graphLine(in size: CGSize, value: KeyPath<TransferSpeedSample, Int>) -> Path {
        guard samples.count > 1 else { return Path() }
        let maximum = max(1, samples.flatMap { [$0.downBps, $0.upBps] }.max() ?? 1)
        var path = Path()
        for (index, sample) in samples.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
            let y = size.height - (size.height * CGFloat(sample[keyPath: value]) / CGFloat(maximum))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

private struct FileTypeIconView: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: FileTypeIconCache.icon(for: path))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

private enum FileTypeIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let key = (ext.isEmpty ? "__document__" : ext) as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let contentType = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: contentType)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private struct CandidatePosterView: View {
    let candidate: TorrentEngine.MetadataCandidate

    var body: some View {
        Group {
            if let url = candidate.posterURL {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .empty:
                        loadingPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
                .id("candidate-poster-\(candidate.id)-\(url.absoluteString)")
            } else {
                placeholder
            }
        }
        .frame(width: 40, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        PosterFallbackView(symbol: candidate.type == .show ? "tv" : "film", cornerRadius: 8)
    }

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
            ProgressView()
                .controlSize(.small)
        }
    }
}

private struct MediaInfoBlock: View {
    let meta: MediaMetadata
    let torrentID: String
    let torrentName: String
    let totalWanted: Int64
    let fileCount: Int
    let skippedFileCount: Int
    let sourceLabel: String
    let onFixMatch: () -> Void
    let onShowDetails: () -> Void

    private var resolvedPosterURL: URL? {
        meta.localPosterPath ?? PosterCache.load(for: torrentID) ?? meta.posterURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                poster

                HStack(spacing: 6) {
                    Button {
                        onFixMatch()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .help("Fix Match")

                    Button {
                        onShowDetails()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .help("Show Details")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 54)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(meta.title)
                        .font(.headline)
                        .lineLimit(2)

                    if let year = meta.year {
                        Text("(\(String(year)))")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: meta.type == .show ? "tv" : "film")
                    Text(meta.type == .show ? "TV Show" : "Movie")
                    if let suffix = meta.displaySuffix, !suffix.isEmpty {
                        Text("•")
                        Text(suffix)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label {
                    Text(torrentName)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "doc")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    Text(formatBytes(totalWanted))
                    Text("•")
                    Text(fileSummary)
                    Text("•")
                    Text(sourceLabel)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var poster: some View {
        Group {
            if let url = resolvedPosterURL {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .empty:
                        loadingPlaceholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
                .id("poster-\(torrentID)-\(url.absoluteString)")
            } else {
                placeholder
            }
        }
        .frame(width: 54, height: 81)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        PosterFallbackView(symbol: meta.type == .show ? "tv" : "film", cornerRadius: 8)
    }

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
            ProgressView()
                .controlSize(.small)
        }
    }

    private var fileSummary: String {
        guard skippedFileCount > 0 else { return "\(fileCount) files" }
        return "\(fileCount) files, \(skippedFileCount) skipped"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

private struct MediaDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meta: MediaMetadata
    let torrentID: String
    let torrentName: String
    @State private var ratings: TraktClient.Ratings?
    @State private var cast: [TraktClient.CastMember] = []
    @State private var isLoadingSupplementalDetails = false

    private var resolvedPosterURL: URL? {
        meta.localPosterPath ?? PosterCache.load(for: torrentID) ?? meta.posterURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Media Details", systemImage: meta.type == .show ? "tv" : "film")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        detailsPoster
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(meta.title + (meta.year.map { " (\($0))" } ?? ""))
                                .font(.title3.weight(.semibold))
                            Text(meta.type == .show ? "TV Show" : "Movie")
                                .foregroundStyle(.secondary)
                            if let suffix = meta.displaySuffix, !suffix.isEmpty {
                                Text(suffix)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let overview = meta.overview, !overview.isEmpty {
                        Text(overview)
                            .foregroundStyle(.secondary)
                    }

                    if let ratings {
                        ratingSection(ratings)
                    }

                    if !cast.isEmpty {
                        castSection
                    } else if isLoadingSupplementalDetails {
                        ProgressView("Loading cast and rating...")
                            .controlSize(.small)
                    }

                    detailsRow("Torrent", torrentName)
                }
                .padding(18)
            }
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 560)
        .background(.regularMaterial)
        .task(id: meta.traktID) {
            await loadSupplementalDetails()
        }
    }

    @ViewBuilder
    private func detailsRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .textSelection(.enabled)
            }
        }
    }

    private var detailsPoster: some View {
        Group {
            if let url = resolvedPosterURL {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        PosterFallbackView(symbol: meta.type == .show ? "tv" : "film", cornerRadius: 14)
                    }
                }
                .id("details-poster-\(torrentID)-\(url.absoluteString)")
            } else {
                PosterFallbackView(symbol: meta.type == .show ? "tv" : "film", cornerRadius: 14)
            }
        }
    }

    private func ratingSection(_ ratings: TraktClient.Ratings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rating", systemImage: "star.fill")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", ratings.rating))
                    .font(.title2.weight(.semibold))
                Text("/ 10")
                    .foregroundStyle(.secondary)
                Text("\(ratings.votes.formatted()) Trakt votes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cast", systemImage: "person.2")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cast) { member in
                        VStack(alignment: .leading, spacing: 5) {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                                .frame(width: 42, height: 42)

                            Text(member.person.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            if let character = member.character, !character.isEmpty {
                                Text(character)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: 106, alignment: .leading)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadSupplementalDetails() async {
        guard let traktID = meta.traktID else { return }
        isLoadingSupplementalDetails = true
        defer { isLoadingSupplementalDetails = false }

        let client = TraktClient(clientID: "eb92f2cb922619e94a4ca0adcfd9572fc0397acb18a33cb6e65b7f2219983d9e")
        let id = String(traktID)

        switch meta.type {
        case .movie:
            async let loadedRatings = try? client.movieRatings(id: id)
            async let loadedPeople = try? client.moviePeople(id: id)
            ratings = await loadedRatings
            if let people = await loadedPeople {
                cast = Array(people.cast.prefix(10))
            }
        case .show:
            async let loadedRatings = try? client.showRatings(id: id)
            async let loadedPeople = try? client.showPeople(id: id)
            ratings = await loadedRatings
            if let people = await loadedPeople {
                cast = Array(people.cast.prefix(10))
            }
        }
    }
}
