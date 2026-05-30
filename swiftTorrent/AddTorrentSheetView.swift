//
//  AddTorrentSheetView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct AddTorrentSheetView: View {
    let initialMagnet: String?
    var onAdd: (_ magnet: String, _ savePath: String, _ category: String?, _ overrideQuery: String?, _ overrideYear: Int?, _ overrideType: MediaMetadata.MediaType?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: TorrentEngine
    @ObservedObject private var settings = AppSettings.shared

    @State private var magnet = ""
    @State private var savePath = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                                   ?? (NSHomeDirectory() + "/Downloads"))
    @State private var savePathWasEdited = false
    @State private var category: String = ""
    @State private var categoryWasEdited = false
    @State private var suppressCategoryTracking = false
    @State private var suppressSavePathTracking = false
    @State private var showingFixMatchSheet = false

    @State private var parsedName = ""
    @State private var overrideQuery = ""
    @State private var overrideYearText = ""
    @State private var overrideType: OverrideType = .auto
    @State private var previewMetadata: MediaMetadata?
    @State private var previewCandidates: [TorrentEngine.MetadataCandidate] = []
    @State private var previewState: PreviewState = .idle
    @State private var analyzeTaskID = UUID()

    private enum OverrideType: String, CaseIterable, Identifiable {
        case auto
        case movie
        case show

        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var mediaType: MediaMetadata.MediaType? {
            switch self {
            case .auto: return nil
            case .movie: return .movie
            case .show: return .show
            }
        }
    }

    private enum PreviewState {
        case idle
        case loading
        case failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add Torrent")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Magnet link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $magnet)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 68)
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08))
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Match Preview")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                previewSection
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save path")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Save path…", text: $savePath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: savePath) { _, _ in
                            if !suppressSavePathTracking {
                                savePathWasEdited = true
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                Picker("Category", selection: $category) {
                    Text("None").tag("")
                    ForEach(settings.categoryDefinitionsForUI) { category in
                        Label(category.title, systemImage: category.symbol).tag(category.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: category) { _, _ in
                    if !suppressCategoryTracking {
                        categoryWasEdited = true
                        if !savePathWasEdited {
                            applyAutomaticSavePathForCategory()
                        }
                    }
                }
            }
                .frame(width: 220, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    let trimmedMagnet = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedPath = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedMagnet.isEmpty, !trimmedPath.isEmpty else { return }

                    onAdd(
                        trimmedMagnet,
                        trimmedPath,
                        category.isEmpty ? nil : category,
                        overrideQueryValue,
                        Int(overrideYearText),
                        selectedOverrideType
                    )
                    dismiss()
                } label: {
                    Label("Add Torrent", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            magnet = initialMagnet ?? ""
            seedOverridesFromParsedName()
            if category.isEmpty {
                applyAutomaticCategory(settings.categoryDefinitionsForUI.first?.id ?? "")
            }
            suppressSavePathTracking = true
            savePath = settings.preferredSavePath(for: category)
            suppressSavePathTracking = false
            savePathWasEdited = false
            categoryWasEdited = false
            analyzeTaskID = UUID()
        }
        .onChange(of: magnet) { _, _ in
            categoryWasEdited = false
            savePathWasEdited = false
            seedOverridesFromParsedName()
            analyzeTaskID = UUID()
        }
        .task(id: analyzeTaskID) {
            try? await Task.sleep(for: .milliseconds(250))
            await refreshPreview()
        }
        .sheet(isPresented: $showingFixMatchSheet) {
            NavigationStack {
                ScrollView {
                    fixMatchEditor
                        .padding()
                }
                .frame(minWidth: 520, idealWidth: 560, minHeight: 420, maxHeight: 720)
                .navigationTitle("Fix Match")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showingFixMatchSheet = false
                        }
                    }
                }
            }
        }
        .onChange(of: showingFixMatchSheet) { _, isShowing in
            guard isShowing else { return }
            Task {
                previewCandidates = await engine.previewMetadataCandidates(
                    query: overrideQueryValue,
                    year: Int(overrideYearText),
                    preferredType: selectedOverrideType
                )
            }
        }
    }

    private var previewSection: some View {
        Group {
            if let previewMetadata {
                HStack(alignment: .top, spacing: 12) {
                    AddPreviewPosterView(url: previewMetadata.posterURL)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(previewMetadata.title)
                                .font(.headline)
                            if let year = previewMetadata.year {
                                Text(verbatim: "(\(year))")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !parsedName.isEmpty {
                            Text(parsedName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if let suffix = previewMetadata.displaySuffix, !suffix.isEmpty {
                            Text(suffix)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let overview = previewMetadata.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }

                    Spacer()

                    Button {
                        showingFixMatchSheet = true
                    } label: {
                        Label("Fix Match", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                HStack(spacing: 10) {
                    switch previewState {
                    case .loading:
                        ProgressView()
                            .controlSize(.small)
                        Text("Matching title and category…")
                            .foregroundStyle(.secondary)
                    case .failed:
                        Image(systemName: "exclamationmark.magnifyingglass")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No match found")
                                .foregroundStyle(.secondary)
                            if !parsedName.isEmpty {
                                Text(parsedName)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button("Fix Match") {
                            showingFixMatchSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    case .idle:
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Paste or open a magnet link to preview its metadata before adding.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var fixMatchEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    Task { await refreshPreview() }
                }
                .buttonStyle(.borderedProminent)

                Button("Search") {
                    Task {
                        previewCandidates = await engine.previewMetadataCandidates(
                            query: overrideQueryValue,
                            year: Int(overrideYearText),
                            preferredType: selectedOverrideType
                        )
                    }
                }
                .buttonStyle(.bordered)

                Button("Parsed") {
                    seedOverridesFromParsedName()
                    Task { await refreshPreview() }
                }
                .buttonStyle(.bordered)

                Button("Clear", role: .destructive) {
                    seedOverridesFromParsedName()
                    Task { await refreshPreview() }
                }
                .buttonStyle(.bordered)
            }

            if !previewCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Candidates")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(previewCandidates) { candidate in
                        Button {
                            overrideQuery = candidate.title
                            overrideYearText = candidate.year.map(String.init) ?? ""
                            overrideType = candidate.type == .movie ? .movie : .show
                            Task {
                                await refreshPreview()
                                showingFixMatchSheet = false
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                AddCandidatePosterView(candidate: candidate)

                                VStack(alignment: .leading, spacing: 2) {
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
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var selectedOverrideType: MediaMetadata.MediaType? {
        overrideType.mediaType ?? parsed.inferredType ?? inferredCategoryType
    }

    private var parsed: TorrentNameParser.Parsed {
        TorrentNameParser.parse(parsedName)
    }

    private var overrideQueryValue: String {
        let trimmed = overrideQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? parsed.query : trimmed
    }

    private var inferredCategoryType: MediaMetadata.MediaType? {
        switch settings.normalizedCategoryValue(category) {
        case "tv":
            return .show
        case "movie":
            return .movie
        default:
            return nil
        }
    }

    private func seedOverridesFromParsedName() {
        parsedName = MagnetKeyExtractor.displayName(from: magnet) ?? ""
        let parsed = TorrentNameParser.parse(parsedName)
        overrideQuery = parsed.query
        overrideYearText = parsed.year.map(String.init) ?? ""
        if let inferredType = parsed.inferredType {
            overrideType = inferredType == .show ? .show : .movie
            if !categoryWasEdited {
                applyAutomaticCategory(inferredType == .show ? "tv" : "movie")
            }
        } else {
            overrideType = .auto
        }
    }

    private func refreshPreview() async {
        let trimmedMagnet = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMagnet.isEmpty else {
            await MainActor.run {
                previewMetadata = nil
                previewState = .idle
            }
            return
        }

        parsedName = MagnetKeyExtractor.displayName(from: trimmedMagnet) ?? ""
        guard !parsedName.isEmpty else {
            await MainActor.run {
                previewMetadata = nil
                previewState = .failed
            }
            return
        }

        await MainActor.run {
            previewState = .loading
        }

        let matched = await engine.previewMetadata(
            query: overrideQueryValue,
            year: Int(overrideYearText),
            preferredType: selectedOverrideType,
            displaySuffix: parsed.suffix
        )

        await MainActor.run {
            previewMetadata = matched
            previewState = matched == nil ? .failed : .idle
            if let matched, !categoryWasEdited {
                applyAutomaticCategory(matched.type == .show ? "tv" : "movie")
            }
            if !savePathWasEdited {
                applyAutomaticSavePathForCategory()
            }
        }
    }

    private func applyAutomaticCategory(_ value: String) {
        suppressCategoryTracking = true
        category = value
        suppressCategoryTracking = false
    }

    private func applyAutomaticSavePathForCategory() {
        suppressSavePathTracking = true
        savePath = settings.preferredSavePath(for: category)
        suppressSavePathTracking = false
    }
}

private struct AddPreviewPosterView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
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
                .id("add-preview-\(url.absoluteString)")
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 108)
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

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
            ProgressView()
                .controlSize(.small)
        }
    }
}

private struct AddCandidatePosterView: View {
    let candidate: TorrentEngine.MetadataCandidate

    var body: some View {
        Group {
            if let url = candidate.posterURL {
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
                .id("add-candidate-\(candidate.id)-\(url.absoluteString)")
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
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
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
