//
//  TorrentEngine.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation
import Combine
import TorrentCore

#if canImport(AppKit)
import AppKit
#endif

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

struct TorrentRow: Identifiable, Hashable {
    let id: String
    let coreIndex: Int
    var name: String
    var progress: Double
    var totalWanted: Int64
    var totalWantedDone: Int64
    var downBps: Int
    var upBps: Int
    var downloadedTotal: Int64
    var uploadedTotal: Int64
    var peers: Int
    var seeds: Int
    var state: Int
    var isSeeding: Bool
    var isPaused: Bool
    var category: String?
}

struct TransferSpeedSample: Identifiable, Hashable {
    let id = UUID()
    let activeSecond: TimeInterval
    let downBps: Int
    let upBps: Int
}

#if canImport(AppKit)
private enum DockOverlayMetricMode: String, CaseIterable {
    case both
    case download
    case upload
    case eta
}

private enum DockOverlayStyleMode: String, CaseIterable {
    case auto
    case colorful
    case dark
    case tinted
    case translucent
}

private final class DockTelemetryView: NSView {
    var line1Text: String = "↓ 0B/s" {
        didSet { needsDisplay = true }
    }
    var line2Text: String? = "↑ 0B/s" {
        didSet { needsDisplay = true }
    }
    var styleMode: DockOverlayStyleMode = .colorful {
        didSet { needsDisplay = true }
    }

    private let iconImage: NSImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        iconImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)

        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]

        let second = line2Text ?? ""
        let sampleWidth = max((line1Text as NSString).size(withAttributes: attrs).width, (second as NSString).size(withAttributes: attrs).width)
        let stripWidth = min(bounds.width - 16, max(72, sampleWidth + 14))
        let stripHeight: CGFloat = line2Text == nil ? 24 : 36
        let stripRect = NSRect(
            x: 6,
            y: 6,
            width: stripWidth,
            height: stripHeight
        )

        let badgePath = NSBezierPath(roundedRect: stripRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.22).setFill()
        let shadowRect = stripRect.offsetBy(dx: 0, dy: -1)
        NSBezierPath(roundedRect: shadowRect, xRadius: 8, yRadius: 8).fill()

        let gradient: NSGradient
        switch styleMode {
        case .colorful:
            gradient = NSGradient(colors: [NSColor.systemGreen.withAlphaComponent(0.96), NSColor.systemMint.withAlphaComponent(0.9)])!
        case .dark:
            gradient = NSGradient(colors: [NSColor(calibratedWhite: 0.18, alpha: 0.95), NSColor(calibratedWhite: 0.08, alpha: 0.95)])!
        case .tinted:
            let tint = NSColor.controlAccentColor
            gradient = NSGradient(colors: [tint.withAlphaComponent(0.95), tint.blended(withFraction: 0.35, of: .black)?.withAlphaComponent(0.9) ?? tint.withAlphaComponent(0.9)])!
        case .translucent:
            gradient = NSGradient(colors: [NSColor.windowBackgroundColor.withAlphaComponent(0.72), NSColor.windowBackgroundColor.withAlphaComponent(0.58)])!
        case .auto:
            gradient = NSGradient(colors: [NSColor.systemGreen.withAlphaComponent(0.96), NSColor.systemMint.withAlphaComponent(0.9)])!
        }
        gradient.draw(in: badgePath, angle: 90)
        NSColor.white.withAlphaComponent(0.14).setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()

        if line2Text != nil {
            let dividerY = stripRect.midY
            let dividerRect = NSRect(x: stripRect.minX + 6, y: dividerY, width: stripRect.width - 12, height: 1)
            NSColor.white.withAlphaComponent(0.12).setFill()
            dividerRect.fill()
        }

        if let secondLine = line2Text {
            let topRect = NSRect(x: stripRect.minX + 2, y: stripRect.midY + 1, width: stripRect.width - 4, height: stripRect.height / 2 - 2)
            let bottomRect = NSRect(x: stripRect.minX + 2, y: stripRect.minY + 1, width: stripRect.width - 4, height: stripRect.height / 2 - 2)
            line1Text.draw(in: topRect, withAttributes: attrs)
            secondLine.draw(in: bottomRect, withAttributes: attrs)
        } else {
            let singleRect = NSRect(x: stripRect.minX + 2, y: stripRect.minY + 3, width: stripRect.width - 4, height: stripRect.height - 6)
            line1Text.draw(in: singleRect, withAttributes: attrs)
        }
    }
}
#endif

struct TorrentFile: Identifiable, Hashable {
    let id: Int
    let path: String
    let size: Int64
    let done: Int64
    let isWanted: Bool
    let isPrioritized: Bool

    var isSkipped: Bool { !isWanted }

    var progress: Double {
        guard size > 0 else { return 0 }
        return min(1.0, max(0.0, Double(done) / Double(size)))
    }
}

@MainActor
final class TorrentEngine: ObservableObject {
    struct MetadataCandidate: Identifiable, Hashable {
        let id: String
        let title: String
        let year: Int?
        let type: MediaMetadata.MediaType
        let overview: String?
        let score: Int
        let traktID: Int?
        let tmdbID: Int?
        let imdbID: String?
        let tvdbID: Int?
        var posterURL: URL?
    }

    enum MetadataLookupState: Equatable {
        case idle
        case loading
        case failed
    }

    @Published var torrents: [TorrentRow] = []
    @Published var filesByTorrentID: [String: [TorrentFile]] = [:]
    @Published var mediaByTorrentID: [String: MediaMetadata] = [:]
    @Published var metadataLookupStateByID: [String: MetadataLookupState] = [:]
    @Published var metadataCandidatesByID: [String: [MetadataCandidate]] = [:]
    @Published private(set) var transferSpeedSamplesByID: [String: [TransferSpeedSample]] = [:]
    @Published var userFacingError: String?

    private var lastProgressByID: [String: Double] = [:]
    private var startedAtByStableKey: [String: Date] = [:]
    private var seedingStartedAtByStableKey: [String: Date] = [:]
    private var idleObservedAtByStableKey: [String: Date] = [:]
    private var idleAutoPausedAtByStableKey: [String: Date] = [:]
    private var idleAutoPausedKeys: Set<String> = []
    private var stalledNotificationKeys: Set<String> = []
    private var unavailableNASPaths: Set<String> = []
    private var didBootstrapCompletionTracking = false
    private var activeTransferSecondsByStableKey: [String: TimeInterval] = [:]

    private var session: STSessionRef?
    private var timer: Timer?

    // Debounced poll — coalesces rapid back-to-back poll requests into one
    private var pendingPoll: DispatchWorkItem?

    // Torrents paused by the download queue (distinct from user-paused)
    private var queuedTorrentKeys: [String] = []
    // Newly added torrents that should be resumed once they appear with a live ID.
    private var pendingAutoResumeKeys: Set<String> = []
    private var fileFilterAppliedKeys: Set<String> = []
    private var automaticallyExcludedFiles: Set<String> = []
    private var appliedFileExclusionRules: [FileExclusionRule] = []
    private var appliedAutoFilterNonMediaFiles = true
    @Published private(set) var boostedTorrentKey: String?

    // MARK: - Pause persistence (by STORED torrent key)
    private let pausedKeysDefaultsKey = "swiftTorrent.pausedTorrentKeys"
    private var desiredPausedKeys: Set<String> = []
    private var didApplyDesiredPauseState = false

    func isQueued(torrentID: String) -> Bool {
        queuedTorrentKeys.contains(stableKey(forLiveTorrentID: torrentID))
    }

    func isBoosted(torrentID: String) -> Bool {
        boostedTorrentKey == stableKey(forLiveTorrentID: torrentID)
    }

    init() {
        session = st_session_create(6881, 6891)

        // Load pause states first (STABLE keys)
        desiredPausedKeys = loadPausedKeys()

        // Re-add saved torrents (don’t re-persist)
        let saved = TorrentStore.load()
        for item in saved {
            _ = addMagnet(item.magnet, savePath: item.savePath, category: item.category, persist: false, restoring: true)
        }

        // Start polling
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.poll() }
        }

        #if canImport(AppKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }

    deinit {
        timer?.invalidate()
        #if canImport(AppKit)
        NotificationCenter.default.removeObserver(self)
        #endif
        if let s = session { st_session_destroy(s) }
    }

    // MARK: - Helpers (TorrentStore lookup)

    private func storeEntry(forLiveTorrentID id: String) -> StoredTorrent? {
        // Your app uses 3 different “ID-ish” concepts, so we try a few matches.
        let items = TorrentStore.load()

        if let exact = items.first(where: { $0.key == id }) { return exact }
        if let byMagKey = items.first(where: { MagnetKeyExtractor.key(from: $0.magnet) == id }) { return byMagKey }
        if let contains = items.first(where: { $0.magnet.contains(id) }) { return contains }

        return nil
    }

    private func stableKey(forLiveTorrentID id: String) -> String {
        storeEntry(forLiveTorrentID: id)?.key ?? id
    }

    private func savePath(forLiveTorrentID id: String) -> String? {
        storeEntry(forLiveTorrentID: id)?.savePath
    }

    private func overrideHint(forLiveTorrentID id: String) -> (query: String?, year: Int?, type: MediaMetadata.MediaType?) {
        guard let entry = storeEntry(forLiveTorrentID: id) else { return (nil, nil, nil) }
        let type: MediaMetadata.MediaType?
        switch entry.overrideType?.lowercased() {
        case "movie":
            type = .movie
        case "show":
            type = .show
        default:
            type = nil
        }
        return (entry.overrideQuery, entry.overrideYear, type)
    }

    private func arrHint(forLiveTorrentID id: String) -> ArrMetadataHint? {
        let stable = stableKey(forLiveTorrentID: id)
        return ArrMetadataStore.find(key: stable) ?? ArrMetadataStore.find(key: id)
    }

    func currentMetadataOverride(for torrentID: String) -> (query: String?, year: Int?, type: MediaMetadata.MediaType?) {
        overrideHint(forLiveTorrentID: torrentID)
    }

    func sourceLabel(for torrentID: String) -> String {
        arrHint(forLiveTorrentID: torrentID)?.source.rawValue.capitalized ?? "Manual"
    }

    // MARK: - Files

    func refreshFiles(for torrentID: String) {
        guard let info = torrents.first(where: { $0.id == torrentID }) else { return }
        let idx = info.coreIndex
        guard idx >= 0, let session else { return }

        let count = Int(st_get_torrent_file_count(session, Int32(idx)))
        guard count > 0 else {
            filesByTorrentID[torrentID] = []
            return
        }

        var out: [TorrentFile] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            var cPath: UnsafePointer<CChar>?
            var size: Int64 = 0
            var done: Int64 = 0
            var wanted = true
            var prioritized = false

            let ok = st_get_torrent_file_info(session, Int32(idx), Int32(i), &cPath, &size, &done, &wanted, &prioritized)
            if ok, let cPath {
                out.append(TorrentFile(id: i, path: String(cString: cPath), size: size, done: done, isWanted: wanted, isPrioritized: prioritized))
            }
        }

        filesByTorrentID[torrentID] = out
    }

    private func applyAutomaticFileFilterIfNeeded(current: [TorrentRow], storedItems: [StoredTorrent]) {
        let settings = AppSettings.shared
        guard settings.autoFilterNonMediaFiles || !settings.fileExclusionRules.isEmpty || !automaticallyExcludedFiles.isEmpty,
              let session else { return }

        if appliedFileExclusionRules != settings.fileExclusionRules ||
            appliedAutoFilterNonMediaFiles != settings.autoFilterNonMediaFiles {
            appliedFileExclusionRules = settings.fileExclusionRules
            appliedAutoFilterNonMediaFiles = settings.autoFilterNonMediaFiles
            fileFilterAppliedKeys.removeAll()
        }

        for row in current {
            let stable = stableKey(forLiveTorrentID: row.id, items: storedItems)
            guard !fileFilterAppliedKeys.contains(stable) else { continue }

            let count = Int(st_get_torrent_file_count(session, Int32(row.coreIndex)))
            guard count > 0 else { continue }

            var filteredAny = false
            var sawAnyFile = false

            for index in 0..<count {
                var cPath: UnsafePointer<CChar>?
                var size: Int64 = 0
                var done: Int64 = 0
                var wanted = true
                var prioritized = false
                guard st_get_torrent_file_info(session, Int32(row.coreIndex), Int32(index), &cPath, &size, &done, &wanted, &prioritized),
                      let cPath else { continue }

                sawAnyFile = true
                let path = String(cString: cPath)
                let exclusionKey = "\(stable):\(index)"
                let shouldDownload = settings.shouldDownloadFile(path: path, category: row.category)
                if wanted && !shouldDownload {
                    _ = row.id.withCString { torrentID in
                        st_torrent_set_file_wanted(session, torrentID, Int32(index), false)
                    }
                    automaticallyExcludedFiles.insert(exclusionKey)
                    filteredAny = true
                } else if !wanted && shouldDownload && automaticallyExcludedFiles.contains(exclusionKey) {
                    _ = row.id.withCString { torrentID in
                        st_torrent_set_file_wanted(session, torrentID, Int32(index), true)
                    }
                    automaticallyExcludedFiles.remove(exclusionKey)
                    filteredAny = true
                }
            }

            guard sawAnyFile else { continue }
            fileFilterAppliedKeys.insert(stable)
            if filteredAny, filesByTorrentID[row.id] != nil {
                refreshFiles(for: row.id)
            }
        }
    }

    // MARK: - Media enrichment (unchanged)

    func enrichIfNeeded(for torrent: TorrentRow) {
        if mediaByTorrentID[torrent.id] != nil { return }
        if metadataLookupStateByID[torrent.id] == .loading { return }
        refreshMetadata(for: torrent)
    }

    func refreshMetadata(for torrent: TorrentRow) {
        mediaByTorrentID[torrent.id] = nil
        metadataLookupStateByID[torrent.id] = .loading

        let parsed = TorrentNameParser.parse(torrent.name)
        let arrHint = arrHint(forLiveTorrentID: torrent.id)
        let defaultTypeHint = inferredTypeHint(category: torrent.category, parsed: parsed)
        let override = overrideHint(forLiveTorrentID: torrent.id)
        let query = override.query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? override.query!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (arrHint?.title ?? parsed.query)
        let year = override.year ?? arrHint?.year ?? parsed.year
        let typeHint = override.type ?? arrHint?.mediaType ?? defaultTypeHint

        Task {
            do {
                let meta = try await resolvedMetadata(
                    query: query,
                    year: year,
                    preferredType: typeHint,
                    displaySuffix: parsed.suffix,
                    arrHint: arrHint
                )
                guard var metaUnwrapped = meta else {
                    await MainActor.run {
                        self.metadataLookupStateByID[torrent.id] = .failed
                    }
                    return
                }

                await MainActor.run {
                    self.mediaByTorrentID[torrent.id] = metaUnwrapped
                    self.metadataLookupStateByID[torrent.id] = .idle
                }

                do {
                    let fanart = FanartClient(apiKey: "40d7d215cf9c6d77743eaf4e3e9942c8")
                    if let poster = try await fanart.posterURL(for: metaUnwrapped) {
                        metaUnwrapped.posterURL = poster
                        await MainActor.run {
                            guard self.mediaByTorrentID[torrent.id] != nil else { return }
                            self.mediaByTorrentID[torrent.id] = metaUnwrapped
                        }

                        if PosterCache.load(for: torrent.id) == nil,
                           let (data, _) = try? await URLSession.shared.data(from: poster),
                           let localURL = try? PosterCache.save(data, torrentID: torrent.id) {
                            metaUnwrapped.localPosterPath = localURL
                            await MainActor.run {
                                guard self.mediaByTorrentID[torrent.id] != nil else { return }
                                self.mediaByTorrentID[torrent.id] = metaUnwrapped
                            }
                        }
                    }
                } catch {
                    // Poster fetch is non-critical. Keep the matched metadata visible.
                }

            } catch {
                await MainActor.run {
                    self.metadataLookupStateByID[torrent.id] = .failed
                }
                return
            }

            if await MainActor.run(body: { self.mediaByTorrentID[torrent.id] == nil }) {
                await MainActor.run {
                    self.metadataLookupStateByID[torrent.id] = .failed
                }
            }
        }
    }

    func setMetadataOverride(for torrentID: String, query: String?, year: Int?, type: MediaMetadata.MediaType?) {
        let stable = stableKey(forLiveTorrentID: torrentID)
        let cleanedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = cleanedQuery?.isEmpty == false ? cleanedQuery : nil
        let normalizedType: String?
        switch type {
        case .movie:
            normalizedType = "movie"
        case .show:
            normalizedType = "show"
        case nil:
            normalizedType = nil
        }
        TorrentStore.updateOverride(key: stable, query: normalizedQuery, year: year, type: normalizedType)
        PosterCache.remove(for: torrentID)
        mediaByTorrentID[torrentID] = nil
        metadataLookupStateByID[torrentID] = .idle
        metadataCandidatesByID[torrentID] = []
        if let torrent = torrents.first(where: { $0.id == torrentID }) {
            refreshMetadata(for: torrent)
        }
    }

    func fetchMetadataCandidates(for torrentID: String, query: String, year: Int?, preferredType: MediaMetadata.MediaType?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            metadataCandidatesByID[torrentID] = []
            return
        }

        Task {
            let candidates = await previewMetadataCandidates(query: trimmed, year: year, preferredType: preferredType)
            await MainActor.run {
                self.metadataCandidatesByID[torrentID] = candidates
            }
        }
    }

    func previewMetadata(query: String, year: Int?, preferredType: MediaMetadata.MediaType?, displaySuffix: String? = nil) async -> MediaMetadata? {
        try? await resolvedMetadata(query: query, year: year, preferredType: preferredType, displaySuffix: displaySuffix)
    }

    func previewMetadataCandidates(query: String, year: Int?, preferredType: MediaMetadata.MediaType?) async -> [MetadataCandidate] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        do {
            let candidates = try await resolvedMetadataCandidates(query: query, year: year, preferredType: preferredType)
            return await metadataCandidatePosters(candidates)
        } catch {
            return []
        }
    }

    private func bestMovieMatch(trakt: TraktClient, query: String, year: Int?) async throws -> TraktClient.SearchResult.Movie? {
        let exact = try await trakt.searchMovies(query: query, year: year)
        let fallback = year == nil ? [] : try await trakt.searchMovies(query: query, year: nil)
        let slugMatches = try await slugMovieMatches(trakt: trakt, query: query, year: year)
        let merged = mergeMovies(exact + fallback + slugMatches)
        let ranked = merged
            .map { ($0, scoreMovie($0, query: query, year: year)) }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        if let year, let candidateYear = best.0.year, abs(year - candidateYear) > 1 {
            return nil
        }
        return best.1 >= 45 ? best.0 : nil
    }

    private func bestShowMatch(trakt: TraktClient, query: String, year: Int?) async throws -> TraktClient.SearchResult.Show? {
        let exact = try await trakt.searchShows(query: query, year: year)
        let fallback = year == nil ? [] : try await trakt.searchShows(query: query, year: nil)
        let slugMatches = try await slugShowMatches(trakt: trakt, query: query, year: year)
        let merged = mergeShows(exact + fallback + slugMatches)
        let ranked = merged
            .map { ($0, scoreShow($0, query: query, year: year)) }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        if let year, let candidateYear = best.0.year, abs(year - candidateYear) > 1 {
            return nil
        }
        return best.1 >= 45 ? best.0 : nil
    }

    private func mergeMovies(_ items: [TraktClient.SearchResult.Movie]) -> [TraktClient.SearchResult.Movie] {
        var seen: Set<String> = []
        return items.filter {
            let key = "\($0.ids.trakt ?? -1)|\($0.ids.tmdb ?? -1)|\($0.title.lowercased())|\($0.year ?? -1)"
            return seen.insert(key).inserted
        }
    }

    private func mergeShows(_ items: [TraktClient.SearchResult.Show]) -> [TraktClient.SearchResult.Show] {
        var seen: Set<String> = []
        return items.filter {
            let key = "\($0.ids.trakt ?? -1)|\($0.ids.tmdb ?? -1)|\($0.title.lowercased())|\($0.year ?? -1)"
            return seen.insert(key).inserted
        }
    }

    private func scoreMovie(_ item: TraktClient.SearchResult.Movie, query: String, year: Int?, identifierHint: ArrMetadataHint? = nil) -> Int {
        scoreTitle(item.title, query: query, year: year, candidateYear: item.year) + identifierMatchScore(
            traktID: item.ids.trakt,
            tmdbID: item.ids.tmdb,
            imdbID: item.ids.imdb,
            tvdbID: item.ids.tvdb,
            hint: identifierHint
        )
    }

    private func scoreShow(_ item: TraktClient.SearchResult.Show, query: String, year: Int?, identifierHint: ArrMetadataHint? = nil) -> Int {
        scoreTitle(item.title, query: query, year: year, candidateYear: item.year) + identifierMatchScore(
            traktID: item.ids.trakt,
            tmdbID: item.ids.tmdb,
            imdbID: item.ids.imdb,
            tvdbID: item.ids.tvdb,
            hint: identifierHint
        )
    }

    private func scoreTitle(_ title: String, query: String, year: Int?, candidateYear: Int?) -> Int {
        let normalizedTitle = normalizeLookupText(title)
        let normalizedQuery = normalizeLookupText(query)

        var score = 0
        if normalizedTitle == normalizedQuery { score += 120 }
        if normalizedTitle.hasPrefix(normalizedQuery) { score += 45 }
        if normalizedTitle.contains(normalizedQuery) { score += 25 }

        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
        let titleTokens = Set(normalizedTitle.split(separator: " ").map(String.init))
        score += queryTokens.intersection(titleTokens).count * 12

        if let year, let candidateYear {
            if year == candidateYear { score += 80 }
            else if abs(year - candidateYear) == 1 { score += 15 }
            else { score -= 25 }
        }

        if normalizedTitle.count < normalizedQuery.count / 2 { score -= 20 }
        return score
    }

    private func identifierMatchScore(traktID: Int?, tmdbID: Int?, imdbID: String?, tvdbID: Int?, hint: ArrMetadataHint?) -> Int {
        guard let hint else { return 0 }

        var score = 0
        if let hintedTMDB = hint.tmdbID, let tmdbID, hintedTMDB == tmdbID { score += 250 }
        if let hintedTVDB = hint.tvdbID, let tvdbID, hintedTVDB == tvdbID { score += 250 }
        if let hintedIMDB = normalizedIMDBID(hint.imdbID),
           let imdbID = normalizedIMDBID(imdbID),
           hintedIMDB == imdbID {
            score += 250
        }
        if let hintedTrakt = hint.traktID, let traktID, hintedTrakt == traktID {
            score += 250
        }
        return score
    }

    private func normalizedIMDBID(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeLookupText(_ text: String) -> String {
        let lowered = text.lowercased()
        let replaced = String(String.UnicodeScalarView(lowered.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? scalar : " "
        }))
        let collapsed = replaced.split(separator: " ").joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func slugMovieMatches(trakt: TraktClient, query: String, year: Int?) async throws -> [TraktClient.SearchResult.Movie] {
        guard let year else { return [] }
        let slug = slugCandidate(for: query, year: year)
        guard let movie = try? await trakt.movie(id: slug) else { return [] }
        return [movie]
    }

    private func slugShowMatches(trakt: TraktClient, query: String, year: Int?) async throws -> [TraktClient.SearchResult.Show] {
        guard let year else { return [] }
        let slug = slugCandidate(for: query, year: year)
        guard let show = try? await trakt.show(id: slug) else { return [] }
        return [show]
    }

    private func slugCandidate(for query: String, year: Int) -> String {
        let normalized = normalizeLookupText(query)
        let base = normalized.replacingOccurrences(of: " ", with: "-")
        return "\(base)-\(year)"
    }

    private func inferredTypeHint(category: String?, parsed: TorrentNameParser.Parsed) -> MediaMetadata.MediaType {
        let c = (category ?? "").lowercased()
        if c.contains("tv") || c.contains("sonarr") { return .show }
        if c.contains("movie") || c.contains("radarr") { return .movie }
        return parsed.inferredType ?? .movie
    }

    private func resolvedMetadata(query: String, year: Int?, preferredType: MediaMetadata.MediaType?, displaySuffix: String?, arrHint: ArrMetadataHint? = nil) async throws -> MediaMetadata? {
        if let arrHint, let arrResolved = try await resolvedArrMetadata(arrHint, displaySuffix: displaySuffix) {
            return arrResolved
        }

        let candidates = try await resolvedMetadataCandidates(query: query, year: year, preferredType: preferredType)
        guard let best = candidates.first else { return nil }
        return MediaMetadata(
            type: best.type,
            title: best.title,
            year: best.year,
            traktID: best.traktID,
            tmdbID: best.tmdbID,
            imdbID: best.imdbID,
            tvdbID: best.tvdbID,
            overview: best.overview,
            posterURL: best.posterURL,
            localPosterPath: nil,
            displaySuffix: displaySuffix
        )
    }

    private func resolvedArrMetadata(_ hint: ArrMetadataHint, displaySuffix: String?) async throws -> MediaMetadata? {
        guard let type = hint.mediaType else { return nil }

        let title = hint.title
        var year = hint.year
        let traktID: Int? = hint.traktID
        var tmdbID = hint.tmdbID
        var imdbID = hint.imdbID
        var tvdbID = hint.tvdbID
        var overview: String?
        var posterURL: URL?

        // Radarr, Sonarr, and Tsuname already resolved the concrete media item.
        // Do not run a title search here; it can override known metadata.
        if let traktID {
            let trakt = TraktClient(clientID: "eb92f2cb922619e94a4ca0adcfd9572fc0397acb18a33cb6e65b7f2219983d9e")
            switch type {
            case .movie:
                if let movie = try? await trakt.movie(id: String(traktID)) {
                    if year == nil { year = movie.year }
                    if tmdbID == nil { tmdbID = movie.ids.tmdb }
                    if imdbID == nil { imdbID = movie.ids.imdb }
                    if tvdbID == nil { tvdbID = movie.ids.tvdb }
                    overview = movie.overview
                    posterURL = try? await FanartClient(apiKey: "40d7d215cf9c6d77743eaf4e3e9942c8").posterURL(for: MediaMetadata(
                        type: type,
                        title: title,
                        year: year,
                        traktID: traktID,
                        tmdbID: tmdbID,
                        imdbID: imdbID,
                        tvdbID: tvdbID,
                        overview: overview,
                        posterURL: nil,
                        localPosterPath: nil,
                        displaySuffix: displaySuffix
                    ))
                }
            case .show:
                if let show = try? await trakt.show(id: String(traktID)) {
                    if year == nil { year = show.year }
                    if tmdbID == nil { tmdbID = show.ids.tmdb }
                    if imdbID == nil { imdbID = show.ids.imdb }
                    if tvdbID == nil { tvdbID = show.ids.tvdb }
                    overview = show.overview
                    posterURL = try? await FanartClient(apiKey: "40d7d215cf9c6d77743eaf4e3e9942c8").posterURL(for: MediaMetadata(
                        type: type,
                        title: title,
                        year: year,
                        traktID: traktID,
                        tmdbID: tmdbID,
                        imdbID: imdbID,
                        tvdbID: tvdbID,
                        overview: overview,
                        posterURL: nil,
                        localPosterPath: nil,
                        displaySuffix: displaySuffix
                    ))
                }
            }
        }

        return MediaMetadata(
            type: type,
            title: title,
            year: year,
            traktID: traktID,
            tmdbID: tmdbID,
            imdbID: imdbID,
            tvdbID: tvdbID,
            overview: overview,
            posterURL: posterURL,
            localPosterPath: nil,
            displaySuffix: displaySuffix
        )
    }

    private func resolvedMetadataCandidates(query: String, year: Int?, preferredType: MediaMetadata.MediaType?, identifierHint: ArrMetadataHint? = nil) async throws -> [MetadataCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trakt = TraktClient(clientID: "eb92f2cb922619e94a4ca0adcfd9572fc0397acb18a33cb6e65b7f2219983d9e")
        var candidates: [MetadataCandidate] = []

        if preferredType != .show {
            let exact = try await trakt.searchMovies(query: trimmed, year: year)
            let fallback = year == nil ? [] : try await trakt.searchMovies(query: trimmed, year: nil)
            let slugMatches = try await slugMovieMatches(trakt: trakt, query: trimmed, year: year)
            let merged = mergeMovies(exact + fallback + slugMatches)
            candidates.append(contentsOf: merged.map {
                MetadataCandidate(id: "movie-\($0.ids.trakt ?? -1)-\($0.ids.tmdb ?? -1)-\($0.title)-\($0.year ?? -1)", title: $0.title, year: $0.year, type: .movie, overview: $0.overview, score: scoreMovie($0, query: trimmed, year: year, identifierHint: identifierHint), traktID: $0.ids.trakt, tmdbID: $0.ids.tmdb, imdbID: $0.ids.imdb, tvdbID: $0.ids.tvdb, posterURL: nil)
            })
        }

        if preferredType != .movie {
            let exact = try await trakt.searchShows(query: trimmed, year: year)
            let fallback = year == nil ? [] : try await trakt.searchShows(query: trimmed, year: nil)
            let slugMatches = try await slugShowMatches(trakt: trakt, query: trimmed, year: year)
            let merged = mergeShows(exact + fallback + slugMatches)
            candidates.append(contentsOf: merged.map {
                MetadataCandidate(id: "show-\($0.ids.trakt ?? -1)-\($0.ids.tmdb ?? -1)-\($0.title)-\($0.year ?? -1)", title: $0.title, year: $0.year, type: .show, overview: $0.overview, score: scoreShow($0, query: trimmed, year: year, identifierHint: identifierHint), traktID: $0.ids.trakt, tmdbID: $0.ids.tmdb, imdbID: $0.ids.imdb, tvdbID: $0.ids.tvdb, posterURL: nil)
            })
        }

        let withPosters = await metadataCandidatePosters(candidates)
        return Array(withPosters.sorted {
            let lhsScore = $0.score + ($0.posterURL == nil ? 0 : 18)
            let rhsScore = $1.score + ($1.posterURL == nil ? 0 : 18)
            if lhsScore == rhsScore {
                return ($0.year ?? 0) > ($1.year ?? 0)
            }
            return lhsScore > rhsScore
        }.prefix(10))
    }

    private func metadataCandidatePosters(_ candidates: [MetadataCandidate]) async -> [MetadataCandidate] {
        guard !candidates.isEmpty else { return [] }
        let fanart = FanartClient(apiKey: "40d7d215cf9c6d77743eaf4e3e9942c8")
        var results = candidates

        await withTaskGroup(of: (String, URL?).self) { group in
            for candidate in candidates {
                group.addTask {
                    let metadata = MediaMetadata(type: candidate.type, title: candidate.title, year: candidate.year, traktID: candidate.traktID, tmdbID: candidate.tmdbID, imdbID: candidate.imdbID, tvdbID: candidate.tvdbID, overview: candidate.overview, posterURL: nil, localPosterPath: nil, displaySuffix: nil)
                    return (candidate.id, try? await fanart.posterURL(for: metadata))
                }
            }

            for await (candidateID, posterURL) in group {
                if let index = results.firstIndex(where: { $0.id == candidateID }) {
                    results[index].posterURL = posterURL
                }
            }
        }

        return results
    }

    // MARK: - Add

    func addMagnet(_ magnet: String, savePath: String, category: String? = nil, persist: Bool = true, restoring: Bool = false, overrideQuery: String? = nil, overrideYear: Int? = nil, overrideType: MediaMetadata.MediaType? = nil) -> String? {
        guard let s = session else { return "Session not initialised" }

        let trimmedMagnet = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMagnet.isEmpty else { return "Empty magnet link" }
        let trimmedSavePath = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSavePath.isEmpty else { return "Save path is empty" }

        if let availabilityError = validateSavePathAvailability(trimmedSavePath) {
            userFacingError = availabilityError
            return availabilityError
        }

        do {
            try FileManager.default.createDirectory(atPath: trimmedSavePath, withIntermediateDirectories: true)
        } catch {
            return "Failed to create save directory: \(error.localizedDescription)"
        }

        // Compute stable key early (info-hash if possible)
        let stable = MagnetKeyExtractor.key(from: trimmedMagnet) ?? trimmedMagnet
        if !restoring, TorrentStore.load().contains(where: { $0.key == stable }) {
            return "This torrent is already present."
        }

        if persist {
            var items = TorrentStore.load()
            let entry = StoredTorrent(
                key: stable,
                magnet: trimmedMagnet,
                savePath: trimmedSavePath,
                category: normalizeCategory(category),
                overrideQuery: overrideQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? overrideQuery?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                overrideYear: overrideYear,
                overrideType: {
                    switch overrideType {
                    case .movie: return "movie"
                    case .show: return "show"
                    case nil: return nil
                    }
                }()
            )
            if let idx = items.firstIndex(where: { $0.key == stable }) { items[idx] = entry }
            else { items.append(entry) }
            TorrentStore.save(items)
        }

        startedAtByStableKey[stable] = Date()

        var errBuf = Array<CChar>(repeating: 0, count: 512)
        let ok = trimmedMagnet.withCString { magnetC in
            trimmedSavePath.withCString { pathC in
                st_add_magnet(s, magnetC, pathC, &errBuf, Int32(errBuf.count))
            }
        }

        guard ok else { return String(cString: errBuf) }

        // Check max active downloads — if we're at the limit, queue this one instead
        if restoring, desiredPausedKeys.contains(stable) {
            _ = stable.withCString { st_torrent_pause(s, $0) }
        } else {
            let maxActive = AppSettings.shared.maxActiveDownloads
            let activeCount = torrents.filter {
                !$0.isPaused &&
                !$0.isSeeding &&
                $0.progress < 0.999 &&
                stableKey(forLiveTorrentID: $0.id) != boostedTorrentKey
            }.count
            if maxActive > 0 && activeCount >= maxActive {
                queuedTorrentKeys.append(stable)
                _ = stable.withCString { st_torrent_pause(s, $0) }
            } else {
                if !restoring {
                    desiredPausedKeys.remove(stable)
                    savePausedKeys(desiredPausedKeys)
                }
                pendingAutoResumeKeys.insert(stable)
            }
        }

        schedulePoll()
        return nil
    }

    func clearUserFacingError() {
        userFacingError = nil
    }

    #if canImport(AppKit)
    func showInFinder(torrentID: String) {
        let stable = stableKey(forLiveTorrentID: torrentID)
        let cleanedPath = AppSettings.shared.cleanedDestination(for: stable)
        let candidate = cleanedPath ?? savePath(forLiveTorrentID: torrentID)
        guard let path = candidate else {
            userFacingError = "No saved download path found for this torrent."
            return
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            userFacingError = "Download folder is unavailable: \(path)"
            return
        }

        if cleanedPath != nil {
            let url = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        // In-progress: prefer the actual torrent payload path under the save root.
        var targetURL = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
        if let row = torrents.first(where: { $0.id == torrentID }) {
            let payloadDir = targetURL.appendingPathComponent(row.name, isDirectory: true)
            var payloadIsDir: ObjCBool = false
            if fm.fileExists(atPath: payloadDir.path, isDirectory: &payloadIsDir) {
                targetURL = payloadDir
            }
        }

        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
    }
    #endif

    // Debounces rapid poll() calls (e.g. when many torrents are added at once)
    private func schedulePoll() {
        pendingPoll?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.poll() }
        pendingPoll = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // MARK: - Controls (persist pause immediately using STABLE key)

    func pauseTorrent(id: String) {
        guard let s = session else { return }
        _ = id.withCString { st_torrent_pause(s, $0) }

        let stable = stableKey(forLiveTorrentID: id)
        queuedTorrentKeys.removeAll { $0 == stable }
        desiredPausedKeys.insert(stable)
        savePausedKeys(desiredPausedKeys)

        poll()
    }

    func resumeTorrent(id: String) {
        guard let s = session else { return }
        _ = id.withCString { st_torrent_resume(s, $0) }

        let stable = stableKey(forLiveTorrentID: id)
        queuedTorrentKeys.removeAll { $0 == stable }
        desiredPausedKeys.remove(stable)
        savePausedKeys(desiredPausedKeys)

        poll()
    }

    func toggleBoost(torrentID: String) {
        let stable = stableKey(forLiveTorrentID: torrentID)
        if boostedTorrentKey == stable {
            boostedTorrentKey = nil
            requeueIfOverActiveLimit(stableKey: stable)
            poll()
            return
        }

        let previousBoostedKey = boostedTorrentKey
        boostedTorrentKey = stable
        queuedTorrentKeys.removeAll { $0 == stable }
        desiredPausedKeys.remove(stable)
        savePausedKeys(desiredPausedKeys)
        if let s = session {
            _ = torrentID.withCString { st_torrent_resume(s, $0) }
        }
        if let previousBoostedKey {
            requeueIfOverActiveLimit(stableKey: previousBoostedKey)
        }
        poll()
    }

    private func requeueIfOverActiveLimit(stableKey: String) {
        let maxActive = AppSettings.shared.maxActiveDownloads
        guard maxActive > 0,
              let s = session,
              let row = torrents.first(where: { self.stableKey(forLiveTorrentID: $0.id) == stableKey }),
              !row.isPaused,
              !row.isSeeding,
              row.progress < 0.999 else { return }

        let normalActiveCount = torrents.filter {
            !$0.isPaused &&
            !$0.isSeeding &&
            $0.progress < 0.999 &&
            self.stableKey(forLiveTorrentID: $0.id) != boostedTorrentKey
        }.count
        guard normalActiveCount > maxActive else { return }

        _ = row.id.withCString { st_torrent_pause(s, $0) }
        if !queuedTorrentKeys.contains(stableKey) {
            queuedTorrentKeys.append(stableKey)
        }
    }

    func removeTorrent(id: String, deleteFiles: Bool, shouldPoll: Bool = true) {
        guard let s = session else { return }
        let stable = stableKey(forLiveTorrentID: id)
        _ = id.withCString { st_torrent_remove(s, $0, deleteFiles) }

        TorrentStore.remove(key: stable)
        ArrMetadataStore.remove(key: stable)
        AppSettings.shared.unmarkCleaned(stable)
        AppSettings.shared.clearRecentCompletionMark(for: stable)
        AppSettings.shared.setCleanedDestination(nil, for: stable)
        desiredPausedKeys.remove(stable)
        if boostedTorrentKey == stable { boostedTorrentKey = nil }
        queuedTorrentKeys.removeAll { $0 == stable }
        pendingAutoResumeKeys.remove(stable)
        startedAtByStableKey[stable] = nil
        seedingStartedAtByStableKey[stable] = nil
        idleObservedAtByStableKey[stable] = nil
        idleAutoPausedAtByStableKey[stable] = nil
        idleAutoPausedKeys.remove(stable)
        savePausedKeys(desiredPausedKeys)
        PosterCache.remove(for: id)
        filesByTorrentID[id] = nil
        mediaByTorrentID[id] = nil
        metadataLookupStateByID[id] = nil
        lastProgressByID[id] = nil
        transferSpeedSamplesByID[id] = nil
        activeTransferSecondsByStableKey[stable] = nil
        fileFilterAppliedKeys.remove(stable)

        if shouldPoll {
            poll()
        }
    }

    func setFileWanted(_ wanted: Bool, torrentID: String, fileID: Int) {
        guard let session else { return }
        _ = torrentID.withCString { st_torrent_set_file_wanted(session, $0, Int32(fileID), wanted) }
        automaticallyExcludedFiles.remove("\(stableKey(forLiveTorrentID: torrentID)):\(fileID)")
        fileFilterAppliedKeys.insert(stableKey(forLiveTorrentID: torrentID))
        refreshFiles(for: torrentID)
        poll()
    }

    func setFilesWanted(_ wanted: Bool, torrentID: String, fileIDs: [Int]) {
        guard let session, !fileIDs.isEmpty else { return }
        let stable = stableKey(forLiveTorrentID: torrentID)
        for fileID in fileIDs {
            _ = torrentID.withCString { st_torrent_set_file_wanted(session, $0, Int32(fileID), wanted) }
            automaticallyExcludedFiles.remove("\(stable):\(fileID)")
        }
        fileFilterAppliedKeys.insert(stable)
        refreshFiles(for: torrentID)
        poll()
    }

    func setFilePrioritized(_ prioritized: Bool, torrentID: String, fileID: Int) {
        guard let session else { return }
        _ = torrentID.withCString { st_torrent_set_file_priority(session, $0, Int32(fileID), prioritized) }
        refreshFiles(for: torrentID)
        poll()
    }

    func setFilesPrioritized(_ prioritized: Bool, torrentID: String, fileIDs: [Int]) {
        guard let session, !fileIDs.isEmpty else { return }
        for fileID in fileIDs {
            _ = torrentID.withCString { st_torrent_set_file_priority(session, $0, Int32(fileID), prioritized) }
        }
        refreshFiles(for: torrentID)
        poll()
    }

    // MARK: - Category

    func setCategory(_ category: String?, for torrentID: String) {
        var items = TorrentStore.load()

        if let idx = items.firstIndex(where: { $0.key == torrentID }) {
            items[idx].category = normalizeCategory(category)
            TorrentStore.save(items)
            fileFilterAppliedKeys.remove(torrentID)
            poll()
            return
        }
        if let idx = items.firstIndex(where: { MagnetKeyExtractor.key(from: $0.magnet) == torrentID }) {
            items[idx].category = normalizeCategory(category)
            TorrentStore.save(items)
            fileFilterAppliedKeys.remove(items[idx].key)
            poll()
            return
        }
        if let idx = items.firstIndex(where: { $0.magnet.contains(torrentID) }) {
            items[idx].category = normalizeCategory(category)
            TorrentStore.save(items)
            fileFilterAppliedKeys.remove(items[idx].key)
            poll()
            return
        }
    }

    private func categoryForTorrent(id: String, items: [StoredTorrent]) -> String? {
        if let exact = items.first(where: { $0.key == id }) { return exact.category }
        return items.first(where: { $0.magnet.contains(id) })?.category
    }

    private func stableKey(forLiveTorrentID id: String, items: [StoredTorrent]) -> String {
        if let exact = items.first(where: { $0.key == id }) { return exact.key }
        if let byMagnetKey = items.first(where: { MagnetKeyExtractor.key(from: $0.magnet) == id }) { return byMagnetKey.key }
        if let contains = items.first(where: { $0.magnet.contains(id) }) { return contains.key }
        return id
    }

    private func normalizeCategory(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty ? nil : t
    }

    // MARK: - Poll

    private func poll() {
        guard let s = session else { return }
        let storedItems = TorrentStore.load()

        let maxItems = 200
        var raw = Array(repeating: STTorrentStatus(), count: maxItems)
        let count = Int(st_get_torrents(s, &raw, Int32(maxItems)))

        guard count > 0 else {
            torrents = []
            updateDockTelemetry(current: [])
            return
        }

        let previous = Dictionary(uniqueKeysWithValues: torrents.map { ($0.id, $0) })

        var rows: [TorrentRow] = []
        rows.reserveCapacity(count)

        for i in 0..<count {
            let st = raw[i]
            let name = String(cString: st_get_torrent_name(s, Int32(i)))
            let id = String(cString: st_get_torrent_id(s, Int32(i)))

            rows.append(
                TorrentRow(
                    id: id,
                    coreIndex: i,
                    name: name,
                    progress: Double(st.progress),
                    totalWanted: Int64(st.total_wanted),
                    totalWantedDone: Int64(st.total_wanted_done),
                    downBps: Int(st.download_rate),
                    upBps: Int(st.upload_rate),
                    downloadedTotal: Int64(st.total_downloaded),
                    uploadedTotal: Int64(st.total_uploaded),
                    peers: Int(st.num_peers),
                    seeds: Int(st.num_seeds),
                    state: Int(st.state),
                    isSeeding: st.is_seeding,
                    isPaused: st.is_paused,
                    category: categoryForTorrent(id: id, items: storedItems)
                )
            )
        }

        torrents = rows
        sampleActiveTransferSpeeds(current: rows, storedItems: storedItems)
        if let boostedTorrentKey,
           let boostedRow = rows.first(where: { stableKey(forLiveTorrentID: $0.id, items: storedItems) == boostedTorrentKey }),
           boostedRow.isSeeding || boostedRow.progress >= 0.999 {
            self.boostedTorrentKey = nil
        }

        for row in rows {
            let stable = stableKey(forLiveTorrentID: row.id, items: storedItems)
            if startedAtByStableKey[stable] == nil {
                startedAtByStableKey[stable] = Date()
            }
            if row.isSeeding {
                if seedingStartedAtByStableKey[stable] == nil {
                    seedingStartedAtByStableKey[stable] = Date()
                }
            } else {
                seedingStartedAtByStableKey[stable] = nil
            }
        }

        if didBootstrapCompletionTracking {
            captureRecentCompletions(previous: previous, current: rows, storedItems: storedItems)
        } else {
            didBootstrapCompletionTracking = true
        }

        applyPendingAutoResumes(current: rows, storedItems: storedItems)
        applyAutomaticFileFilterIfNeeded(current: rows, storedItems: storedItems)
        handleIdleDownloadManagement(current: rows, storedItems: storedItems)
        notifyNASAvailabilityIfNeeded(storedItems: storedItems)

        // Promote queued torrents when a download slot is free
        promoteQueuedIfNeeded()

        // ✅ Apply desired pause/resume once (slight delay helps libtorrent “settle”)
        if !didApplyDesiredPauseState {
            didApplyDesiredPauseState = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.applyDesiredPauseStateUsingStoredKeys()
            }
        }

        autoCleanupIfNeeded(previous: previous, current: rows)
        autoRemoveSeededIfNeeded(current: rows, storedItems: storedItems)
        updateDockTelemetry(current: rows)

        for t in rows { lastProgressByID[t.id] = t.progress }
    }

    private func sampleActiveTransferSpeeds(current: [TorrentRow], storedItems: [StoredTorrent]) {
        for row in current {
            guard !row.isPaused, !row.isSeeding, row.progress < 0.999 else { continue }
            let stable = stableKey(forLiveTorrentID: row.id, items: storedItems)
            let activeSecond = (activeTransferSecondsByStableKey[stable] ?? 0) + 1
            activeTransferSecondsByStableKey[stable] = activeSecond
            var samples = transferSpeedSamplesByID[row.id] ?? []
            samples.append(TransferSpeedSample(activeSecond: activeSecond, downBps: row.downBps, upBps: row.upBps))
            if samples.count > 180 {
                samples.removeFirst(samples.count - 180)
            }
            transferSpeedSamplesByID[row.id] = samples
        }
    }

    private func autoRemoveSeededIfNeeded(current: [TorrentRow], storedItems: [StoredTorrent]) {
        let settings = AppSettings.shared
        let evaluateTime = settings.autoRemoveAfterSeedTime && settings.seedTimeLimitMinutes > 0
        let evaluateRatio = settings.autoRemoveAfterSeedRatio && settings.seedRatioLimit > 0
        guard evaluateTime || evaluateRatio else { return }

        let cutoff = TimeInterval(settings.seedTimeLimitMinutes * 60)
        let now = Date()
        var removeIDs: [String] = []

        for row in current {
            guard row.isSeeding else { continue }
            let stable = stableKey(forLiveTorrentID: row.id, items: storedItems)

            var shouldRemove = false

            if evaluateTime, let seededAt = seedingStartedAtByStableKey[stable] {
                if now.timeIntervalSince(seededAt) >= cutoff {
                    shouldRemove = true
                }
            }

            if !shouldRemove, evaluateRatio, row.downloadedTotal > 0 {
                let ratio = Double(row.uploadedTotal) / Double(row.downloadedTotal)
                if ratio >= settings.seedRatioLimit {
                    shouldRemove = true
                }
            }

            if shouldRemove {
                AppNotificationCenter.shared.send(
                    .autoRemove,
                    title: "Torrent removed after seeding",
                    body: row.name,
                    identifier: "auto-remove-\(stable)"
                )
                removeIDs.append(row.id)
            }
        }

        guard !removeIDs.isEmpty else { return }
        for id in removeIDs {
            removeTorrent(id: id, deleteFiles: false, shouldPoll: false)
        }
        schedulePoll()
    }

    private func applyPendingAutoResumes(current: [TorrentRow], storedItems: [StoredTorrent]) {
        guard !pendingAutoResumeKeys.isEmpty, let s = session else { return }

        for row in current {
            let stable = stableKey(forLiveTorrentID: row.id, items: storedItems)
            guard pendingAutoResumeKeys.contains(stable) else { continue }

            // Respect queue/user pause decisions.
            if queuedTorrentKeys.contains(stable) || desiredPausedKeys.contains(stable) {
                pendingAutoResumeKeys.remove(stable)
                continue
            }

            if row.isPaused {
                _ = row.id.withCString { st_torrent_resume(s, $0) }
            } else {
                pendingAutoResumeKeys.remove(stable)
            }
        }
    }

    private func captureRecentCompletions(previous: [String: TorrentRow], current: [TorrentRow], storedItems: [StoredTorrent]) {
        for t in current {
            let was = previous[t.id]?.progress ?? lastProgressByID[t.id] ?? 0
            let isComplete = t.progress >= 0.999
            guard isComplete, was < 0.999 else { continue }

            let stable = stableKey(forLiveTorrentID: t.id, items: storedItems)
            let meta = mediaByTorrentID[t.id]
            let startedAt = startedAtByStableKey[stable]
            let completedAt = Date()
            let duration = startedAt.map { max(0, completedAt.timeIntervalSince($0)) }

            let item = RecentDownloadItem(
                id: UUID(),
                torrentKey: stable,
                torrentName: t.name,
                title: meta?.title ?? TorrentNameParser.parse(t.name).query,
                year: meta?.year,
                typeRaw: {
                    switch meta?.type {
                    case .show:
                        return "show"
                    default:
                        return "movie"
                    }
                }(),
                posterLocalPath: meta?.localPosterPath?.path,
                posterRemoteURL: meta?.posterURL?.absoluteString,
                startedAt: startedAt,
                completedAt: completedAt,
                durationSeconds: duration,
                outcome: AppSettings.shared.autoCleanupEnabled ? "Completed (cleanup queued)" : "Completed",
                cleanedDestinationPath: AppSettings.shared.cleanedDestination(for: stable),
                source: ArrMetadataStore.find(key: stable)?.source.rawValue.capitalized ?? "Manual"
            )
            AppSettings.shared.appendRecentDownload(item)
            AppNotificationCenter.shared.send(
                .completion,
                title: "Download complete",
                body: t.name,
                identifier: "completion-\(stable)"
            )
        }
    }

    private func applyDesiredPauseStateUsingStoredKeys() {
        guard let s = session else { return }

        // Only re-apply explicit user pauses. Non-paused torrents are handled by restore + queue policy.
        let saved = TorrentStore.load()
        for item in saved {
            let key = item.key
            if desiredPausedKeys.contains(key) {
                _ = key.withCString { st_torrent_pause(s, $0) }
            }
        }

        // refresh UI state after applying
        poll()
    }

    private func handleIdleDownloadManagement(current: [TorrentRow], storedItems: [StoredTorrent]) {
        let settings = AppSettings.shared
        guard settings.autoManageIdleDownloads, let s = session else {
            idleObservedAtByStableKey.removeAll()
            idleAutoPausedAtByStableKey.removeAll()
            idleAutoPausedKeys.removeAll()
            return
        }

        let now = Date()
        let idleCutoff = TimeInterval(max(1, settings.idleDownloadMinutes) * 60)
        let resumeCutoff = TimeInterval(max(1, settings.idleResumeMinutes) * 60)
        let activeStable = Set(current.map { stableKey(forLiveTorrentID: $0.id, items: storedItems) })

        idleObservedAtByStableKey = idleObservedAtByStableKey.filter { activeStable.contains($0.key) }
        idleAutoPausedAtByStableKey = idleAutoPausedAtByStableKey.filter { activeStable.contains($0.key) }
        idleAutoPausedKeys = idleAutoPausedKeys.intersection(activeStable)
        stalledNotificationKeys = stalledNotificationKeys.intersection(activeStable)

        for row in current {
            let stable = stableKey(forLiveTorrentID: row.id, items: storedItems)

            if row.isPaused {
                if idleAutoPausedKeys.contains(stable),
                   let pausedAt = idleAutoPausedAtByStableKey[stable],
                   now.timeIntervalSince(pausedAt) >= resumeCutoff {
                    _ = row.id.withCString { st_torrent_resume(s, $0) }
                    idleAutoPausedKeys.remove(stable)
                    idleAutoPausedAtByStableKey[stable] = nil
                    idleObservedAtByStableKey[stable] = nil
                }
                continue
            }

            let isDownloadCandidate = !row.isSeeding && row.progress < 0.999
            guard isDownloadCandidate else {
                idleObservedAtByStableKey[stable] = nil
                idleAutoPausedAtByStableKey[stable] = nil
                idleAutoPausedKeys.remove(stable)
                continue
            }

            let hasActivity = row.downBps > 0 || row.upBps > 0 || row.peers > 0
            if hasActivity {
                idleObservedAtByStableKey[stable] = nil
                stalledNotificationKeys.remove(stable)
                continue
            }

            if idleObservedAtByStableKey[stable] == nil {
                idleObservedAtByStableKey[stable] = now
            }

            guard !idleAutoPausedKeys.contains(stable),
                  !desiredPausedKeys.contains(stable),
                  !queuedTorrentKeys.contains(stable),
                  let idleSince = idleObservedAtByStableKey[stable],
                  now.timeIntervalSince(idleSince) >= idleCutoff else { continue }

            _ = row.id.withCString { st_torrent_pause(s, $0) }
            idleAutoPausedKeys.insert(stable)
            idleAutoPausedAtByStableKey[stable] = now
            idleObservedAtByStableKey[stable] = nil
            queuedTorrentKeys.append(stable)
            if stalledNotificationKeys.insert(stable).inserted {
                AppNotificationCenter.shared.send(
                    .stalledDownload,
                    title: "Download stalled",
                    body: "\(row.name) has been idle and was paused temporarily.",
                    identifier: "stalled-\(stable)"
                )
            }
        }
    }

    private func notifyNASAvailabilityIfNeeded(storedItems: [StoredTorrent]) {
        let currentUnavailable = Set(storedItems.compactMap { item -> String? in
            let path = item.savePath
            guard path.hasPrefix("/Volumes/"),
                  validateSavePathAvailability(path) != nil else { return nil }
            return path
        })

        for path in currentUnavailable.subtracting(unavailableNASPaths) {
            let volume = path.split(separator: "/").dropFirst().first.map(String.init) ?? path
            AppNotificationCenter.shared.send(
                .nasDisconnected,
                title: "NAS disconnected",
                body: "Cannot reach '\(volume)'. Downloads using this volume will wait until it reconnects.",
                identifier: "nas-disconnected-\(volume)"
            )
        }
        unavailableNASPaths = currentUnavailable
    }

    private func promoteQueuedIfNeeded() {
        guard !queuedTorrentKeys.isEmpty, let s = session else { return }
        let maxActive = AppSettings.shared.maxActiveDownloads
        guard maxActive > 0 else {
            // Unlimited — flush the whole queue
            for key in queuedTorrentKeys {
                _ = key.withCString { st_torrent_resume(s, $0) }
            }
            queuedTorrentKeys.removeAll()
            return
        }
        if AppSettings.shared.queueManagementMode == "automatic" {
            queuedTorrentKeys.sort { lhs, rhs in
                let lhsRow = torrents.first { stableKey(forLiveTorrentID: $0.id) == lhs }
                let rhsRow = torrents.first { stableKey(forLiveTorrentID: $0.id) == rhs }
                return (lhsRow?.progress ?? 0) > (rhsRow?.progress ?? 0)
            }
        }

        let activeCount = torrents.filter {
            !$0.isPaused &&
            !$0.isSeeding &&
            $0.progress < 0.999 &&
            stableKey(forLiveTorrentID: $0.id) != boostedTorrentKey
        }.count
        var available = maxActive - activeCount
        while available > 0, !queuedTorrentKeys.isEmpty {
            let key = queuedTorrentKeys.removeFirst()
            if desiredPausedKeys.contains(key) { continue }
            _ = key.withCString { st_torrent_resume(s, $0) }
            available -= 1
        }
    }

    // MARK: - Pause persistence internals

    private func loadPausedKeys() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: pausedKeysDefaultsKey) ?? []
        return Set(arr)
    }

    private func savePausedKeys(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: pausedKeysDefaultsKey)
    }

    #if canImport(AppKit)
    @objc private func appWillTerminate() {
        // Persist only explicit user pauses (not queue or idle auto-pauses).
        savePausedKeys(desiredPausedKeys)
    }
    #endif

    #if canImport(AppKit)
    private func updateDockTelemetry(current: [TorrentRow]) {
        let activeDownloads = current.filter { !$0.isPaused && !$0.isSeeding && $0.progress < 0.999 }
        let activeCount = activeDownloads.count
        let totalDown = max(0, current.reduce(0) { $0 + $1.downBps })
        let totalUp = max(0, current.reduce(0) { $0 + $1.upBps })
        let settings = AppSettings.shared
        NSApp.dockTile.badgeLabel = settings.dockShowActiveCountBadge && activeCount > 0 ? "\(activeCount)" : nil

        let downLabel = compactRateLabel(bytesPerSecond: totalDown)
        let upLabel = compactRateLabel(bytesPerSecond: totalUp)

        if settings.dockShowTransferOverlay {
            let telemetryView: DockTelemetryView
            if let existing = NSApp.dockTile.contentView as? DockTelemetryView {
                telemetryView = existing
            } else {
                telemetryView = DockTelemetryView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                NSApp.dockTile.contentView = telemetryView
            }
            let metricMode = DockOverlayMetricMode(rawValue: settings.dockOverlayMetricMode) ?? .both
            let styleMode = resolveOverlayStyleMode(from: settings)
            telemetryView.styleMode = styleMode
            switch metricMode {
            case .both:
                telemetryView.line1Text = "↓ \(downLabel)/s"
                telemetryView.line2Text = "↑ \(upLabel)/s"
            case .download:
                telemetryView.line1Text = "↓ \(downLabel)/s"
                telemetryView.line2Text = nil
            case .upload:
                telemetryView.line1Text = "↑ \(upLabel)/s"
                telemetryView.line2Text = nil
            case .eta:
                telemetryView.line1Text = "ETA"
                telemetryView.line2Text = totalETAString(for: activeDownloads, totalDownBps: totalDown)
            }
        } else {
            NSApp.dockTile.contentView = nil
        }
        NSApp.dockTile.display()
    }

    private func resolveOverlayStyleMode(from settings: AppSettings) -> DockOverlayStyleMode {
        let raw = DockOverlayStyleMode(rawValue: settings.dockOverlayStyleMode) ?? .auto
        guard raw == .auto else { return raw }
        let appearanceName = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if appearanceName == .darkAqua {
            return .dark
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return .translucent
        }
        return .colorful
    }

    private func totalETAString(for activeDownloads: [TorrentRow], totalDownBps: Int) -> String {
        guard totalDownBps > 0 else { return "Waiting…" }
        let remaining = activeDownloads.reduce(Int64(0)) { partial, row in
            partial + max(Int64(0), row.totalWanted - row.totalWantedDone)
        }
        guard remaining > 0 else { return "Done" }
        let seconds = Double(remaining) / Double(totalDownBps)
        return shortDuration(seconds: seconds)
    }

    private func shortDuration(seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private func compactRateLabel(bytesPerSecond: Int) -> String {
        let value = max(0, Double(bytesPerSecond))
        if value >= 1024 * 1024 * 1024 {
            return String(format: "%.1fG", (value / (1024 * 1024 * 1024)).rounded(toPlaces: 1))
        }
        if value >= 1024 * 1024 {
            return String(format: "%.1fM", (value / (1024 * 1024)).rounded(toPlaces: 1))
        }
        if value >= 1024 {
            return String(format: "%.0fK", (value / 1024).rounded())
        }
        return "\(Int(value.rounded()))B"
    }
    #endif

    // MARK: - Manual cleanup

    func cleanupNow(torrentID: String) {
        organizeNow(torrentID: torrentID)
    }

    func cleanupPreview(torrentID: String, destinationOverride: URL? = nil) -> TorrentCleanup.CleanupPlan? {
        guard let meta = mediaByTorrentID[torrentID] else { return nil }
        guard let t = torrents.first(where: { $0.id == torrentID }) else { return nil }

        if filesByTorrentID[torrentID] == nil {
            refreshFiles(for: torrentID)
        }
        let files = filesByTorrentID[torrentID] ?? []
        let relPaths = files.filter { !$0.isSkipped }.map(\.path)

        guard let savePath = savePath(forLiveTorrentID: torrentID) else {
            return nil
        }

        let saveRoot = URL(fileURLWithPath: savePath, isDirectory: true)
        let parsed = TorrentNameParser.parse(t.name)
        let hint = arrHint(forLiveTorrentID: torrentID)
        let appSettings = AppSettings.shared
        let fallback = destinationOverride ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let cleanupSettings = TorrentCleanup.CleanupSettings(
            moviesRoot: destinationOverride ?? appSettings.moviesURL() ?? fallback,
            tvRoot: destinationOverride ?? appSettings.tvURL() ?? fallback,
            mode: .move,
            collision: .rename
        )

        return try? TorrentCleanup.preview(
                saveRoot: saveRoot,
                filePaths: relPaths,
                meta: meta,
                parsedSeason: cleanupSeason(parsed: parsed, hint: hint),
                category: t.category,
                settings: cleanupSettings
        )
    }

    func organizeNow(torrentID: String, destinationOverride: URL? = nil) {
        guard let meta = mediaByTorrentID[torrentID],
              let t = torrents.first(where: { $0.id == torrentID }),
              let savePath = savePath(forLiveTorrentID: torrentID) else {
            userFacingError = "Cleanup details are not available for this torrent yet."
            AppNotificationCenter.shared.send(
                .cleanupFailure,
                title: "Cleanup failed",
                body: "Cleanup details are not available for this torrent yet.",
                identifier: "cleanup-failed-\(torrentID)"
            )
            return
        }
        if filesByTorrentID[torrentID] == nil { refreshFiles(for: torrentID) }
        let relPaths = (filesByTorrentID[torrentID] ?? []).filter { !$0.isSkipped }.map(\.path)
        let saveRoot = URL(fileURLWithPath: savePath, isDirectory: true)
        let appSettings = AppSettings.shared
        guard destinationOverride != nil || (appSettings.moviesURL() != nil && appSettings.tvURL() != nil) else {
            userFacingError = "Set Movies and TV cleanup destinations in Settings first."
            notifyCleanupFailure(torrentName: t.name, reason: "Set Movies and TV cleanup destinations in Settings first.")
            return
        }
        let fallback = destinationOverride ?? URL(fileURLWithPath: savePath, isDirectory: true)
        let cleanupSettings = TorrentCleanup.CleanupSettings(
            moviesRoot: destinationOverride ?? appSettings.moviesURL() ?? fallback,
            tvRoot: destinationOverride ?? appSettings.tvURL() ?? fallback,
            mode: .move,
            collision: .rename
        )

        do {
            let parsed = TorrentNameParser.parse(t.name)
            let hint = arrHint(forLiveTorrentID: torrentID)
            let dest = try TorrentCleanup.run(
                torrentID: torrentID,
                saveRoot: saveRoot,
                filePaths: relPaths,
                meta: meta,
                parsedSeason: cleanupSeason(parsed: parsed, hint: hint),
                category: t.category,
                settings: cleanupSettings
            )
            print("Cleanup OK -> \(dest.path)")
            let stable = stableKey(forLiveTorrentID: torrentID)
            appSettings.setCleanedDestination(dest.path, for: stable)
            appSettings.markCleaned(stable)
        } catch {
            userFacingError = "Cleanup failed: \(error.localizedDescription)"
            AppNotificationCenter.shared.send(
                .cleanupFailure,
                title: "Cleanup failed",
                body: "\(t.name): \(error.localizedDescription)",
                identifier: "cleanup-failed-\(torrentID)"
            )
        }
    }

    // MARK: - Auto-cleanup on completion

    private func autoCleanupIfNeeded(previous: [String: TorrentRow], current: [TorrentRow]) {
        let settings = AppSettings.shared
        guard settings.autoCleanupEnabled else { return }

        for t in current {
            let was = previous[t.id]?.progress ?? lastProgressByID[t.id] ?? 0
            let isComplete = t.progress >= 0.999

            // Only on transition to complete
            guard isComplete, was < 0.999 else { continue }

            let stable = stableKey(forLiveTorrentID: t.id)

            // Only once per torrent (stable key)
            if settings.cleanedTorrentKeys.contains(stable) { continue }

            // Ensure metadata exists (if not, kick enrichment + retry shortly)
            if mediaByTorrentID[t.id] == nil {
                enrichIfNeeded(for: t)

                Task { [weak self] in
                    guard let self else { return }

                    // quick retries to allow enrichment fetch
                    for _ in 0..<6 {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                        if await MainActor.run(body: { self.mediaByTorrentID[t.id] != nil }) {
                            break
                        }
                    }

                    let ok = await self.runCleanupUsingSettings(liveTorrentID: t.id)
                    if ok {
                        await MainActor.run {
                            settings.markCleaned(stable)
                            PosterCache.remove(for: t.id)
                        }
                    }
                }

                continue
            }

            Task { [weak self] in
                guard let self else { return }
                let ok = await self.runCleanupUsingSettings(liveTorrentID: t.id)
                if ok {
                    await MainActor.run {
                        settings.markCleaned(stable)
                        PosterCache.remove(for: t.id)
                    }
                }
            }
        }
    }

    private func runCleanupUsingSettings(liveTorrentID: String) async -> Bool {
        let settings = AppSettings.shared

        guard let t = await MainActor.run(body: { self.torrents.first(where: { $0.id == liveTorrentID }) }) else { return false }
        guard let meta = await MainActor.run(body: { self.mediaByTorrentID[liveTorrentID] }) else {
            notifyCleanupFailure(torrentName: t.name, reason: "Media details could not be loaded.")
            return false
        }

        guard let moviesRoot = settings.moviesURL(),
              let tvRoot = settings.tvURL() else {
            print("Cleanup: destinations not set in Settings.")
            notifyCleanupFailure(torrentName: t.name, reason: "Cleanup destinations are not available.")
            return false
        }

        await MainActor.run { self.refreshFiles(for: liveTorrentID) }
        let files = await MainActor.run { self.filesByTorrentID[liveTorrentID] ?? [] }
        let relPaths = files.map(\.path)
        if relPaths.isEmpty {
            print("Cleanup: no file list.")
            notifyCleanupFailure(torrentName: t.name, reason: "No downloadable files were available.")
            return false
        }

        guard let savePath = savePath(forLiveTorrentID: liveTorrentID) else {
            print("Cleanup: no savePath in store.")
            notifyCleanupFailure(torrentName: t.name, reason: "The saved download folder could not be found.")
            return false
        }
        let saveRoot = URL(fileURLWithPath: savePath, isDirectory: true)

        let parsed = TorrentNameParser.parse(t.name)
        let hint = await MainActor.run { self.arrHint(forLiveTorrentID: liveTorrentID) }

        let cleanupSettings = TorrentCleanup.CleanupSettings(
            moviesRoot: moviesRoot,
            tvRoot: tvRoot,
            mode: .move,
            collision: .rename
        )

        let moviesAccess = moviesRoot.startAccessingSecurityScopedResource()
        let tvAccess = tvRoot.startAccessingSecurityScopedResource()
        defer {
            if moviesAccess { moviesRoot.stopAccessingSecurityScopedResource() }
            if tvAccess { tvRoot.stopAccessingSecurityScopedResource() }
        }

        do {
            let dest = try TorrentCleanup.run(
                torrentID: liveTorrentID,
                saveRoot: saveRoot,
                filePaths: relPaths,
                meta: meta,
                parsedSeason: cleanupSeason(parsed: parsed, hint: hint),
                category: t.category,
                settings: cleanupSettings
            )
            print("Cleanup OK -> \(dest.path)")
            let stable = stableKey(forLiveTorrentID: liveTorrentID)
            await MainActor.run {
                AppSettings.shared.setCleanedDestination(dest.path, for: stable)
            }
            return true
        } catch {
            print("Cleanup failed: \(error.localizedDescription)")
            notifyCleanupFailure(torrentName: t.name, reason: error.localizedDescription)
            return false
        }
    }

    private func cleanupSeason(parsed: TorrentNameParser.Parsed, hint: ArrMetadataHint?) -> Int? {
        guard let hint else { return parsed.season }

        let requestedSeasons = Set(hint.seasons)
        if requestedSeasons.count == 1 {
            return requestedSeasons.first
        }

        let episodeSeasons = Set(hint.episodes.map(\.season))
        if episodeSeasons.count == 1 {
            return episodeSeasons.first
        }

        let scope = hint.scope?.lowercased()
        if scope == "show" || requestedSeasons.count > 1 || episodeSeasons.count > 1 {
            return nil
        }

        return parsed.season
    }

    private func notifyCleanupFailure(torrentName: String, reason: String) {
        AppNotificationCenter.shared.send(
            .cleanupFailure,
            title: "Cleanup failed",
            body: "\(torrentName): \(reason)"
        )
    }

    private func validateSavePathAvailability(_ path: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue {
                return "Save path is not a folder: \(path)"
            }
            return nil
        }

        if path.hasPrefix("/Volumes/") {
            let parts = path.split(separator: "/")
            if parts.count >= 2 {
                let mountName = String(parts[1])
                let mountRoot = "/Volumes/\(mountName)"
                var mountIsDir: ObjCBool = false
                if !fm.fileExists(atPath: mountRoot, isDirectory: &mountIsDir) || !mountIsDir.boolValue {
                    return "Cannot reach network volume '\(mountName)'. Reconnect it and try again."
                }
            }
        }

        return nil
    }
}
