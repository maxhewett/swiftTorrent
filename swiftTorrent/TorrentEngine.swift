//
//  TorrentEngine.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation
import Combine
import TorrentCore

struct TorrentRow: Identifiable, Equatable {
    let id: String
    let name: String

    let progress: Double

    let totalWanted: Int64
    let totalWantedDone: Int64

    let downBps: Int
    let upBps: Int

    let peers: Int
    let seeds: Int

    let state: Int
    let isSeeding: Bool

    let category: String?
}

@MainActor
final class TorrentEngine: ObservableObject {
    @Published var torrents: [TorrentRow] = []

    private var session: STSessionRef?
    private var timer: Timer?

    init() {
        session = st_session_create(6881, 6891)

        // Restore previously saved torrents
        let saved = TorrentStore.load()
        for item in saved {
            _ = addMagnet(item.magnet, savePath: item.savePath, category: item.category, persist: false)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.poll() }
        }
    }

    deinit {
        timer?.invalidate()
        if let s = session { st_session_destroy(s) }
    }

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
            let entry = StoredTorrent(
                key: key,
                magnet: trimmedMagnet,
                savePath: savePath,
                category: normalizeCategory(category)
            )

            if let idx = items.firstIndex(where: { $0.key == key }) {
                items[idx] = entry
            } else {
                items.append(entry)
            }

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
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    category: categoryForTorrent(id: id)
                )
            )
        }

        torrents = rows
    }
}
