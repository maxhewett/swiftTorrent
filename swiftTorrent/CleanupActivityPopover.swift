import SwiftUI

struct CleanupActivityPopover: View {
    @ObservedObject var engine: TorrentEngine
    @ObservedObject private var settings = AppSettings.shared
    let onFixMatch: (CleanupHistoryEntry) -> Void
    @State private var showsErrorsOnly = false

    private var visibleHistory: [CleanupHistoryEntry] {
        showsErrorsOnly ? settings.cleanupHistory.filter { !$0.succeeded || $0.errorMessage != nil } : settings.cleanupHistory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup")
                        .font(.title3.weight(.semibold))
                    Text(engine.cleanupActivityMessage ?? "Organize files and review recent activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if engine.isCleanupScanRunning {
                    if engine.isCleanupPaused {
                        Button("Resume") { engine.toggleCleanupPause() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Pause") { engine.toggleCleanupPause() }
                            .buttonStyle(.bordered)
                    }
                    Button("Stop", role: .destructive) { engine.stopCleanup() }
                        .buttonStyle(.bordered)
                } else if engine.isCleanupRunning {
                    ProgressView().controlSize(.small)
                }
                Button {
                    engine.startManualCleanupScan()
                } label: {
                    Label("Scan Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(engine.isCleanupScanRunning || engine.isCleanupRunning)
            }

            Divider()

            HStack {
                Text("Recent activity")
                    .font(.headline)
                Spacer()
                Toggle("Errors", isOn: $showsErrorsOnly)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(showsErrorsOnly ? "Showing errors only" : "Show errors only")
                Text("Errors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !settings.cleanupHistory.isEmpty {
                    Button("Clear") { settings.clearCleanupHistory() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if visibleHistory.isEmpty {
                if showsErrorsOnly, !settings.cleanupHistory.isEmpty {
                    ContentUnavailableView("No cleanup errors", systemImage: "checkmark.circle", description: Text("All recorded cleanup items succeeded."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                ContentUnavailableView("No cleanup history", systemImage: "broom", description: Text("Cleanup results and errors will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleHistory) { entry in
                            CleanupHistoryRow(entry: entry) {
                                onFixMatch(entry)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
    }
}

private struct CleanupHistoryRow: View {
    let entry: CleanupHistoryEntry
    let onFixMatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(entry.itemName, systemImage: entry.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.succeeded ? Color.primary : Color.orange)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text("From  \(sourceDescription)")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(sourceDescription)
            if let destinationPath = entry.destinationPath {
                Label(destinationPath, systemImage: "arrow.right")
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(destinationPath)
            }
            if let errorMessage = entry.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                if !entry.relativePaths.isEmpty {
                    Button("Fix Match…", action: onFixMatch)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }

    private var sourceDescription: String {
        guard let relativePath = entry.relativePaths.first else { return entry.sourceRootPath }
        if entry.relativePaths.count == 1 {
            return URL(fileURLWithPath: entry.sourceRootPath).appendingPathComponent(relativePath).path
        }
        return "\(entry.sourceRootPath) (\(entry.relativePaths.count) files)"
    }
}

struct CleanupMatchFixSheet: View {
    let entry: CleanupHistoryEntry
    @ObservedObject var engine: TorrentEngine
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var yearText: String
    @State private var typeSelection: String
    @State private var candidates: [TorrentEngine.MetadataCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var isSearching = false
    @State private var errorMessage: String?

    init(entry: CleanupHistoryEntry, engine: TorrentEngine) {
        self.entry = entry
        self.engine = engine
        _query = State(initialValue: entry.query)
        _yearText = State(initialValue: entry.year.map(String.init) ?? "")
        _typeSelection = State(initialValue: entry.mediaType == .show ? "show" : "movie")
    }

    private var selectedType: MediaMetadata.MediaType { typeSelection == "show" ? .show : .movie }
    private var selectedCandidate: TorrentEngine.MetadataCandidate? {
        candidates.first(where: { $0.id == selectedCandidateID })
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.035), .black.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fix Cleanup Match")
                            .font(.title3.weight(.semibold))
                        Text(entry.sourceRootPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    TextField("Title", text: $query)
                        .textFieldStyle(.roundedBorder)
                    TextField("Year", text: $yearText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                    Picker("Type", selection: $typeSelection) {
                        Text("Movie").tag("movie")
                        Text("TV").tag("show")
                    }
                    .labelsHidden()
                    .frame(width: 105)
                    Button("Search") { search() }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
                .padding(.bottom, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text("\(entry.relativePaths.count) file(s) will be organized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if engine.isCleanupRunning { ProgressView().controlSize(.small) }
                    Button("Organize Files") { organize() }
                        .buttonStyle(.borderedProminent)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 14)
            }
            .padding(22)
            .frame(minWidth: 620, minHeight: 520)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .padding(18)
        }
    }

    private func candidateRow(_ candidate: TorrentEngine.MetadataCandidate) -> some View {
        let isSelected = candidate.id == selectedCandidateID
        return Button {
            selectedCandidateID = candidate.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(candidate.title)\(candidate.year.map { " (\($0))" } ?? "")")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(candidate.type == .movie ? "Movie" : "TV Show") · \(candidate.providers.sorted().joined(separator: " + ")) · Match \(candidate.score)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func search() {
        isSearching = true
        errorMessage = nil
        let year = Int(yearText)
        Task {
            candidates = await engine.previewMetadataCandidates(query: query, year: year, preferredType: selectedType)
            selectedCandidateID = candidates.first?.id
            if candidates.isEmpty { errorMessage = "No candidates found. Check the title, year, media type, and provider settings." }
            isSearching = false
        }
    }

    private func organize() {
        errorMessage = nil
        Task {
            let error = await engine.retryFolderCleanup(
                entry: entry,
                query: query,
                year: Int(yearText),
                type: selectedType,
                selectedCandidate: selectedCandidate
            )
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}
