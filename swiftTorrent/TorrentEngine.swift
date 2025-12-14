//
//  TorrentEngine.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation
import Combine
import TorrentCore

struct TorrentRow: Identifiable {
    let id = UUID()
    let name: String
    let progress: Double
    let downBps: Int
    let upBps: Int
    let peers: Int
    let seeds: Int
    let state: Int
    let isSeeding: Bool
}

@MainActor
final class TorrentEngine: ObservableObject {
    @Published var torrents: [TorrentRow] = []

    private var session: STSessionRef?
    private var timer: Timer?

    init() {
        session = st_session_create(6881, 6891)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Timer callback isn't guaranteed to be on MainActor in Swift 6.
            DispatchQueue.main.async {
                self.poll()
            }
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil

        if let s = session {
            st_session_destroy(s)
            session = nil
        }
    }

    func addMagnet(_ magnet: String, savePath: String) -> String? {
        guard let s = session else { return "Session not initialised" }

        var errBuf = Array<CChar>(repeating: 0, count: 512)

        let ok = magnet.withCString { magnetC in
            savePath.withCString { pathC in
                st_add_magnet(s, magnetC, pathC, &errBuf, Int32(errBuf.count))
            }
        }

        return ok ? nil : String(cString: errBuf)
    }

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

            rows.append(
                TorrentRow(
                    name: name,
                    progress: Double(st.progress),
                    downBps: Int(st.download_rate),
                    upBps: Int(st.upload_rate),
                    peers: Int(st.num_peers),
                    seeds: Int(st.num_seeds),
                    state: Int(st.state),
                    isSeeding: st.is_seeding
                )
            )
        }

        torrents = rows
    }
}
