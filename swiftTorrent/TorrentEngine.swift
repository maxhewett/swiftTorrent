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

struct TorrentRow: Identifiable, Hashable {
    let id: String
    let coreIndex: Int
    var name: String
    var progress: Double
    var totalWanted: Int64
    var totalWantedDone: Int64
    var downBps: Int
    var upBps: Int
    var peers: Int
    var seeds: Int
    var state: Int
    var isSeeding: Bool
    var isPaused: Bool
    var category: String?
}

struct TorrentFile: Identifiable, Hashable {
    let id: Int
    let path: String
    let size: Int64
    let done: Int64

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

    private var lastProgressByID: [String: Double] = [:]

    private var session: STSessionRef?
    private var timer: Timer?

    // Debounced poll — coalesces rapid back-to-back poll requests into one
    private var pendingPoll: DispatchWorkItem?

    // Torrents paused by the download queue (distinct from user-paused)
    private var queuedTorrentKeys: [String] = []

    // MARK: - Pause persistence (by STORED torrent key)
    private let pausedKeysDefaultsKey = "swiftTorrent.pausedTorrentKeys"
    private var desiredPausedKeys: Set<String> = []
    private var didApplyDesiredPauseState = false

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

            let ok = st_get_torrent_file_info(session, Int32(idx), Int32(i), &cPath, &size, &done)
            if ok, let cPath {
                out.append(TorrentFile(id: i, path: String(cString: cPath), size: size, done: done))
            }
        }

        filesByTorrentID[torrentID] = out
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
                var meta = try await resolvedMetadata(
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

    private func scoreMovie(_ item: TraktClient.SearchResult.Movie, query: String, year: Int?) -> Int {
        scoreTitle(item.title, query: query, year: year, candidateYear: item.year)
    }

    private func scoreShow(_ item: TraktClient.SearchResult.Show, query: String, year: Int?) -> Int {
        scoreTitle(item.title, query: query, year: year, candidateYear: item.year)
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

        var title = hint.title
        var year = hint.year
        var traktID: Int?
        var tmdbID = hint.tmdbID
        var imdbID = hint.imdbID
        var tvdbID = hint.tvdbID
        var overview: String?
        var posterURL: URL?

        if let fallback = try await resolvedMetadataCandidates(query: hint.title, year: hint.year, preferredType: type).first {
            traktID = fallback.traktID
            if tmdbID == nil { tmdbID = fallback.tmdbID }
            if imdbID == nil { imdbID = fallback.imdbID }
            if tvdbID == nil { tvdbID = fallback.tvdbID }
            if overview == nil { overview = fallback.overview }
            if posterURL == nil { posterURL = fallback.posterURL }
            if title.isEmpty { title = fallback.title }
            if year == nil { year = fallback.year }
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

    private func resolvedMetadataCandidates(query: String, year: Int?, preferredType: MediaMetadata.MediaType?) async throws -> [MetadataCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trakt = TraktClient(clientID: "eb92f2cb922619e94a4ca0adcfd9572fc0397acb18a33cb6e65b7f2219983d9e")
        var candidates: [MetadataCandidate] = []

        if preferredType != .show {
            let exact = try await trakt.searchMovies(query: trimmed, year: year)
            let fallback = year == nil ? [] : try await trakt.searchMovies(query: trimmed, year: nil)
            let slugMatches = try await slugMovieMatches(trakt: trakt, query: trimmed, year: year)
            let merged = mergeMovies(exact + fallback + slugMatches)
            candidates.append(contentsOf: merged.map {
                MetadataCandidate(id: "movie-\($0.ids.trakt ?? -1)-\($0.ids.tmdb ?? -1)-\($0.title)-\($0.year ?? -1)", title: $0.title, year: $0.year, type: .movie, overview: $0.overview, score: scoreMovie($0, query: trimmed, year: year), traktID: $0.ids.trakt, tmdbID: $0.ids.tmdb, imdbID: $0.ids.imdb, tvdbID: $0.ids.tvdb, posterURL: nil)
            })
        }

        if preferredType != .movie {
            let exact = try await trakt.searchShows(query: trimmed, year: year)
            let fallback = year == nil ? [] : try await trakt.searchShows(query: trimmed, year: nil)
            let slugMatches = try await slugShowMatches(trakt: trakt, query: trimmed, year: year)
            let merged = mergeShows(exact + fallback + slugMatches)
            candidates.append(contentsOf: merged.map {
                MetadataCandidate(id: "show-\($0.ids.trakt ?? -1)-\($0.ids.tmdb ?? -1)-\($0.title)-\($0.year ?? -1)", title: $0.title, year: $0.year, type: .show, overview: $0.overview, score: scoreShow($0, query: trimmed, year: year), traktID: $0.ids.trakt, tmdbID: $0.ids.tmdb, imdbID: $0.ids.imdb, tvdbID: $0.ids.tvdb, posterURL: nil)
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

        do {
            try FileManager.default.createDirectory(atPath: savePath, withIntermediateDirectories: true)
        } catch {
            return "Failed to create save directory: \(error.localizedDescription)"
        }

        // Compute stable key early (info-hash if possible)
        let stable = MagnetKeyExtractor.key(from: trimmedMagnet) ?? trimmedMagnet

        if persist {
            var items = TorrentStore.load()
            let entry = StoredTorrent(
                key: stable,
                magnet: trimmedMagnet,
                savePath: savePath,
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

        var errBuf = Array<CChar>(repeating: 0, count: 512)
        let ok = trimmedMagnet.withCString { magnetC in
            savePath.withCString { pathC in
                st_add_magnet(s, magnetC, pathC, &errBuf, Int32(errBuf.count))
            }
        }

        guard ok else { return String(cString: errBuf) }

        // Check max active downloads — if we're at the limit, queue this one instead
        if restoring, desiredPausedKeys.contains(stable) {
            _ = stable.withCString { st_torrent_pause(s, $0) }
        } else {
            let maxActive = AppSettings.shared.maxActiveDownloads
            let activeCount = torrents.filter { !$0.isPaused && !$0.isSeeding && $0.progress < 0.999 }.count
            if maxActive > 0 && activeCount >= maxActive {
                queuedTorrentKeys.append(stable)
                _ = stable.withCString { st_torrent_pause(s, $0) }
            } else {
                if !restoring {
                    desiredPausedKeys.remove(stable)
                    savePausedKeys(desiredPausedKeys)
                }
                _ = stable.withCString { st_torrent_resume(s, $0) }
            }
        }

        schedulePoll()
        return nil
    }

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
        desiredPausedKeys.remove(stable)
        savePausedKeys(desiredPausedKeys)

        poll()
    }

    func removeTorrent(id: String, deleteFiles: Bool) {
        guard let s = session else { return }
        let stable = stableKey(forLiveTorrentID: id)
        _ = id.withCString { st_torrent_remove(s, $0, deleteFiles) }

        TorrentStore.remove(key: stable)
        ArrMetadataStore.remove(key: stable)
        AppSettings.shared.unmarkCleaned(stable)
        AppSettings.shared.unhideTorrent(stable)
        desiredPausedKeys.remove(stable)
        queuedTorrentKeys.removeAll { $0 == stable }
        savePausedKeys(desiredPausedKeys)
        PosterCache.remove(for: id)
        filesByTorrentID[id] = nil
        mediaByTorrentID[id] = nil
        metadataLookupStateByID[id] = nil
        lastProgressByID[id] = nil

        poll()
    }

    // MARK: - Category

    func setCategory(_ category: String?, for torrentID: String) {
        var items = TorrentStore.load()

        if let idx = items.firstIndex(where: { $0.key == torrentID }) {
            items[idx].category = normalizeCategory(category)
            TorrentStore.save(items)
            poll()
            return
        }
        if let idx = items.firstIndex(where: { MagnetKeyExtractor.key(from: $0.magnet) == torrentID }) {
            items[idx].category = normalizeCategory(category)
            TorrentStore.save(items)
            poll()
            return
        }
        if let idx = items.firstIndex(where: { $0.magnet.contains(torrentID) }) {
            items[idx].category = normalizeCategory(category)
            TorrentStore.save(items)
            poll()
            return
        }
    }

    private func categoryForTorrent(id: String) -> String? {
        let items = TorrentStore.load()
        if let exact = items.first(where: { $0.key == id }) { return exact.category }
        return items.first(where: { $0.magnet.contains(id) })?.category
    }

    private func normalizeCategory(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty ? nil : t
    }

    // MARK: - Poll

    private func poll() {
        guard let s = session else { return }

        let maxItems = 200
        var raw = Array(repeating: STTorrentStatus(), count: maxItems)
        let count = Int(st_get_torrents(s, &raw, Int32(maxItems)))

        guard count > 0 else {
            torrents = []
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
                    peers: Int(st.num_peers),
                    seeds: Int(st.num_seeds),
                    state: Int(st.state),
                    isSeeding: st.is_seeding,
                    isPaused: st.is_paused,
                    category: categoryForTorrent(id: id)
                )
            )
        }

        torrents = rows

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

        for t in rows { lastProgressByID[t.id] = t.progress }
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
        let activeCount = torrents.filter { !$0.isPaused && !$0.isSeeding && $0.progress < 0.999 }.count
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
        // Save stable keys for paused torrents
        let pausedStable = Set(torrents.filter { $0.isPaused }.map { stableKey(forLiveTorrentID: $0.id) })
        savePausedKeys(pausedStable)
    }
    #endif

    // MARK: - Manual cleanup trigger (unchanged-ish, but uses stable lookup)

    func cleanupNow(torrentID: String) {
        guard let meta = mediaByTorrentID[torrentID] else { return }
        guard let t = torrents.first(where: { $0.id == torrentID }) else { return }

        if filesByTorrentID[torrentID] == nil {
            refreshFiles(for: torrentID)
        }
        let files = filesByTorrentID[torrentID] ?? []
        let relPaths = files.map(\.path)

        guard let savePath = savePath(forLiveTorrentID: torrentID) else {
            print("Cleanup: no savePath for \(torrentID)")
            return
        }

        let saveRoot = URL(fileURLWithPath: savePath, isDirectory: true)

        let parsed = TorrentNameParser.parse(t.name)

        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let settings = TorrentCleanup.CleanupSettings(
            moviesRoot: base.appendingPathComponent("swiftTorrent Movies", isDirectory: true),
            tvRoot: base.appendingPathComponent("swiftTorrent TV", isDirectory: true),
            mode: .move,
            collision: .rename
        )

        do {
            let dest = try TorrentCleanup.run(
                torrentID: torrentID,
                saveRoot: saveRoot,
                filePaths: relPaths,
                meta: meta,
                parsedSeason: parsed.season,
                category: t.category,
                settings: settings
            )
            print("Cleanup OK -> \(dest.path)")
        } catch {
            print("Cleanup failed: \(error.localizedDescription)")
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
                            settings.hideTorrent(stable)
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
                        settings.hideTorrent(stable)
                        PosterCache.remove(for: t.id)
                    }
                }
            }
        }
    }

    private func runCleanupUsingSettings(liveTorrentID: String) async -> Bool {
        let settings = AppSettings.shared

        guard let meta = await MainActor.run(body: { self.mediaByTorrentID[liveTorrentID] }) else { return false }
        guard let t = await MainActor.run(body: { self.torrents.first(where: { $0.id == liveTorrentID }) }) else { return false }

        guard let moviesRoot = settings.moviesURL(),
              let tvRoot = settings.tvURL() else {
            print("Cleanup: destinations not set in Settings.")
            return false
        }

        await MainActor.run { self.refreshFiles(for: liveTorrentID) }
        let files = await MainActor.run { self.filesByTorrentID[liveTorrentID] ?? [] }
        let relPaths = files.map(\.path)
        if relPaths.isEmpty {
            print("Cleanup: no file list.")
            return false
        }

        guard let savePath = savePath(forLiveTorrentID: liveTorrentID) else {
            print("Cleanup: no savePath in store.")
            return false
        }
        let saveRoot = URL(fileURLWithPath: savePath, isDirectory: true)

        let parsed = TorrentNameParser.parse(t.name)

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
                parsedSeason: parsed.season,
                category: t.category,
                settings: cleanupSettings
            )
            print("Cleanup OK -> \(dest.path)")
            return true
        } catch {
            print("Cleanup failed: \(error.localizedDescription)")
            return false
        }
    }
}
