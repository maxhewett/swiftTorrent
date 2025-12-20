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
    @Published var torrents: [TorrentRow] = []
    @Published var filesByTorrentID: [String: [TorrentFile]] = [:]
    @Published var mediaByTorrentID: [String: MediaMetadata] = [:]

    private var lastProgressByID: [String: Double] = [:]

    private var session: STSessionRef?
    private var timer: Timer?

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
            _ = addMagnet(item.magnet, savePath: item.savePath, category: item.category, persist: false)
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

        let c = (torrent.category ?? "").lowercased()
        let typeHint: MediaMetadata.MediaType =
            (c.contains("tv") || c.contains("sonarr")) ? .show :
            (c.contains("movie") || c.contains("radarr")) ? .movie :
            .movie

        let parsed = TorrentNameParser.parse(torrent.name)

        Task {
            do {
                let trakt = TraktClient(clientID: "eb92f2cb922619e94a4ca0adcfd9572fc0397acb18a33cb6e65b7f2219983d9e")
                let fanart = FanartClient(apiKey: "40d7d215cf9c6d77743eaf4e3e9942c8")

                var meta: MediaMetadata?

                switch typeHint {
                case .movie:
                    if let m = try await trakt.searchMovie(query: parsed.query, year: parsed.year) {
                        meta = MediaMetadata(
                            type: .movie,
                            title: m.title,
                            year: m.year,
                            traktID: m.ids.trakt,
                            tmdbID: m.ids.tmdb,
                            imdbID: m.ids.imdb,
                            tvdbID: m.ids.tvdb,
                            overview: m.overview,
                            posterURL: nil,
                            displaySuffix: parsed.suffix
                        )
                    } else if let s = try await trakt.searchShow(query: parsed.query, year: parsed.year) {
                        meta = MediaMetadata(
                            type: .show,
                            title: s.title,
                            year: s.year,
                            traktID: s.ids.trakt,
                            tmdbID: s.ids.tmdb,
                            imdbID: s.ids.imdb,
                            tvdbID: s.ids.tvdb,
                            overview: s.overview,
                            posterURL: nil,
                            displaySuffix: parsed.suffix
                        )
                    }

                case .show:
                    if let s = try await trakt.searchShow(query: parsed.query, year: parsed.year) {
                        meta = MediaMetadata(
                            type: .show,
                            title: s.title,
                            year: s.year,
                            traktID: s.ids.trakt,
                            tmdbID: s.ids.tmdb,
                            imdbID: s.ids.imdb,
                            tvdbID: s.ids.tvdb,
                            overview: s.overview,
                            posterURL: nil,
                            displaySuffix: parsed.suffix
                        )
                    } else if let m = try await trakt.searchMovie(query: parsed.query, year: parsed.year) {
                        meta = MediaMetadata(
                            type: .movie,
                            title: m.title,
                            year: m.year,
                            traktID: m.ids.trakt,
                            tmdbID: m.ids.tmdb,
                            imdbID: m.ids.imdb,
                            tvdbID: m.ids.tvdb,
                            overview: m.overview,
                            posterURL: nil,
                            displaySuffix: parsed.suffix
                        )
                    }
                }

                guard var metaUnwrapped = meta else { return }

                if let poster = try await fanart.posterURL(for: metaUnwrapped) {
                    metaUnwrapped.posterURL = poster
                }

                await MainActor.run {
                    self.mediaByTorrentID[torrent.id] = metaUnwrapped
                }

            } catch {
                // ignore for now
            }
        }
    }

    // MARK: - Add

    func addMagnet(_ magnet: String, savePath: String, category: String? = nil, persist: Bool = true) -> String? {
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
            let entry = StoredTorrent(key: stable, magnet: trimmedMagnet, savePath: savePath, category: normalizeCategory(category))
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

        // ✅ Ensure it starts
        desiredPausedKeys.remove(stable)
        savePausedKeys(desiredPausedKeys)
        _ = stable.withCString { st_torrent_resume(s, $0) }

        poll()
        return nil
    }

    // MARK: - Controls (persist pause immediately using STABLE key)

    func pauseTorrent(id: String) {
        guard let s = session else { return }
        _ = id.withCString { st_torrent_pause(s, $0) }

        let stable = stableKey(forLiveTorrentID: id)
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
        _ = id.withCString { st_torrent_remove(s, $0, deleteFiles) }

        let stable = stableKey(forLiveTorrentID: id)
        desiredPausedKeys.remove(stable)
        savePausedKeys(desiredPausedKeys)

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

        // Enforce pause/resume by STORED keys (stable across relaunch)
        let saved = TorrentStore.load()
        for item in saved {
            let key = item.key
            if desiredPausedKeys.contains(key) {
                _ = key.withCString { st_torrent_pause(s, $0) }
            } else {
                _ = key.withCString { st_torrent_resume(s, $0) }
            }
        }

        // refresh UI state after applying
        poll()
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
                        await MainActor.run { settings.markCleaned(stable) }
                    }
                }

                continue
            }

            Task { [weak self] in
                guard let self else { return }
                let ok = await self.runCleanupUsingSettings(liveTorrentID: t.id)
                if ok {
                    await MainActor.run { settings.markCleaned(stable) }
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
