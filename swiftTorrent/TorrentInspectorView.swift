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
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedCategory = ""
    @State private var showingMatchSheet = false
    @State private var showingFiles = false
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

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsSection
                    categorySection
                    filesSection
                }
                .padding()
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

    private var header: some View {
        Group {
            if let meta = engine.mediaByTorrentID[torrent.id] {
                MediaInfoBlock(meta: meta, torrentID: torrent.id, torrentName: torrent.name) {
                    showingMatchSheet = true
                }
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
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $showingFiles) {
                VStack(alignment: .leading, spacing: 10) {
                    if files.isEmpty {
                        Text("No file list available yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(files.prefix(8)) { file in
                                fileRow(file)
                            }

                            if files.count > 8 {
                                Text("\(files.count - 8) more files hidden")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if skippedFilesCount > 0 {
                                HStack(spacing: 6) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                    Text("\(skippedFilesCount) skipped \(skippedFilesCount == 1 ? "file" : "files")")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 260, alignment: .topLeading)
                        .clipped()
                    }
                }
            } label: {
                HStack {
                    Text("Files")
                    Spacer()
                    if !files.isEmpty {
                        Text("\(files.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var files: [TorrentFile] {
        engine.filesByTorrentID[torrent.id] ?? []
    }

    private var skippedFilesCount: Int {
        files.filter(\.isSkipped).count
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
        let pathURL = URL(fileURLWithPath: file.path)
        let filename = pathURL.lastPathComponent
        let parentPath = pathURL.deletingLastPathComponent().path
        let showParent = parentPath != "." && parentPath != "/"

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(filename)
                        .font(.body)
                        .lineLimit(1)

                    if file.isSkipped {
                        Text("Skipped")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                if showParent {
                    Text(parentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if file.isSkipped {
                    Text("\(formatBytes(file.size)) excluded from download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if file.progress >= 0.999 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("Download complete")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                } else {
                    ProgressView(value: file.progress)
                        .animation(nil, value: file.progress)

                    Text("\(formatBytes(file.done)) / \(formatBytes(file.size))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Button {
                    engine.setFileWanted(file.isSkipped, torrentID: torrent.id, fileID: file.id)
                } label: {
                    Image(systemName: file.isSkipped ? "arrow.down.circle" : "slash.circle")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help(file.isSkipped ? "Include this file in the download" : "Skip this file")
            }
            .padding(.top, 2)
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
    let onFixMatch: () -> Void

    private var resolvedPosterURL: URL? {
        meta.localPosterPath ?? PosterCache.load(for: torrentID) ?? meta.posterURL
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                poster

                Button {
                    onFixMatch()
                } label: {
                    Label("Fix Match", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
            }

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

                Text(torrentName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

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
        .padding(.vertical, 4)
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
        .frame(width: 70, height: 105)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        PosterFallbackView(symbol: meta.type == .show ? "tv" : "film", cornerRadius: 10)
    }

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
            ProgressView()
                .controlSize(.small)
        }
    }
}
