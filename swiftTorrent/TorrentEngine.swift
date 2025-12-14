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

    private var session: STSessionRef?
    private var timer: Timer?

    // MARK: - Pause persistence
    private let pausedKeysDefaultsKey = "swiftTorrent.pausedTorrentKeys"

    init() {
        session = st_session_create(6881, 6891)

        // Load persisted pause set FIRST
        let pausedKeys = loadPausedKeys()

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

        // Enforce pause/resume after things have had a moment to appear in the session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.applyPausedKeys(pausedKeys)
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
    
    func enrichIfNeeded(for torrent: TorrentRow) {
        // already cached
        if mediaByTorrentID[torrent.id] != nil { return }

        // crude hint from category (you can refine later)
        let c = (torrent.category ?? "").lowercased()
        let typeHint: MediaMetadata.MediaType =
            (c.contains("tv") || c.contains("sonarr")) ? .show :
            (c.contains("movie") || c.contains("radarr")) ? .movie :
            .movie

        let parsed = TorrentNameParser.parse(torrent.name)

        Task {
            do {
                // TODO: move clientID into settings later
                let trakt = TraktClient(clientID: "eb92f2cb922619e94a4ca0adcfd9572fc0397acb18a33cb6e65b7f2219983d9e")

                switch typeHint {
                case .movie:
                    if let m = try await trakt.searchMovie(query: parsed.query, year: parsed.year) {
                        let meta = MediaMetadata(
                            type: .movie,
                            title: m.title,
                            year: m.year,
                            traktID: m.ids.trakt,
                            tmdbID: m.ids.tmdb,
                            overview: m.overview,
                            posterURL: nil
                        )
                        await MainActor.run { self.mediaByTorrentID[torrent.id] = meta }
                    } else {
                        // fallback: try show search if movie fails
                        if let s = try await trakt.searchShow(query: parsed.query, year: parsed.year) {
                            let meta = MediaMetadata(
                                type: .show,
                                title: s.title,
                                year: s.year,
                                traktID: s.ids.trakt,
                                tmdbID: s.ids.tmdb,
                                overview: s.overview,
                                posterURL: nil
                            )
                            await MainActor.run { self.mediaByTorrentID[torrent.id] = meta }
                        }
                    }

                case .show:
                    if let s = try await trakt.searchShow(query: parsed.query, year: parsed.year) {
                        let meta = MediaMetadata(
                            type: .show,
                            title: s.title,
                            year: s.year,
                            traktID: s.ids.trakt,
                            tmdbID: s.ids.tmdb,
                            overview: s.overview,
                            posterURL: nil
                        )
                        await MainActor.run { self.mediaByTorrentID[torrent.id] = meta }
                    } else {
                        // fallback: try movie
                        if let m = try await trakt.searchMovie(query: parsed.query, year: parsed.year) {
                            let meta = MediaMetadata(
                                type: .movie,
                                title: m.title,
                                year: m.year,
                                traktID: m.ids.trakt,
                                tmdbID: m.ids.tmdb,
                                overview: m.overview,
                                posterURL: nil
                            )
                            await MainActor.run { self.mediaByTorrentID[torrent.id] = meta }
                        }
                    }
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

        if persist {
            var items = TorrentStore.load()
            let key = MagnetKeyExtractor.key(from: trimmedMagnet) ?? trimmedMagnet
            let entry = StoredTorrent(key: key, magnet: trimmedMagnet, savePath: savePath, category: normalizeCategory(category))
            if let idx = items.firstIndex(where: { $0.key == key }) { items[idx] = entry }
            else { items.append(entry) }
            TorrentStore.save(items)
        }

        var errBuf = Array<CChar>(repeating: 0, count: 512)
        let ok = trimmedMagnet.withCString { magnetC in
            savePath.withCString { pathC in
                st_add_magnet(s, magnetC, pathC, &errBuf, Int32(errBuf.count))
            }
        }
        return ok ? nil : String(cString: errBuf)
    }

    // MARK: - Controls

    func pauseTorrent(id: String) {
        guard let s = session else { return }
        id.withCString { st_torrent_pause(s, $0) }
        poll()
    }

    func resumeTorrent(id: String) {
        guard let s = session else { return }
        id.withCString { st_torrent_resume(s, $0) }
        poll()
    }

    func removeTorrent(id: String, deleteFiles: Bool) {
        guard let s = session else { return }
        id.withCString { st_torrent_remove(s, $0, deleteFiles) }
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
    }

    // MARK: - Pause persistence internals

    private func loadPausedKeys() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: pausedKeysDefaultsKey) ?? []
        return Set(arr)
    }

    private func savePausedKeys(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: pausedKeysDefaultsKey)
    }

    /// Enforce: anything not in pausedKeys should be resumed.
    private func applyPausedKeys(_ pausedKeys: Set<String>) {
        guard session != nil else { return }

        // Resume everything that shouldn't be paused, and pause the ones that should.
        // We use TorrentStore keys (usually infohash) as the control IDs.
        let saved = TorrentStore.load()
        for item in saved {
            let key = item.key

            if pausedKeys.contains(key) {
                key.withCString { st_torrent_pause(session, $0) }
            } else {
                key.withCString { st_torrent_resume(session, $0) }
            }
        }

        poll()
    }

    #if canImport(AppKit)
    @objc private func appWillTerminate() {
        // Snapshot current pause states
        let paused = Set(torrents.filter { $0.isPaused }.map(\.id))
        savePausedKeys(paused)
    }
    #endif
}
