//
//  TransmissionRPC.swift
//  swiftTorrent
//
//  Created by Max Hewett on 17/12/2025.
//  Emulates transmission RPC for sonarr/radarr compatibility
//

import Foundation
import Swifter

@MainActor
final class TransmissionRPC {
    private weak var engine: TorrentEngine?
    private var transmissionSessionID = UUID().uuidString

    func attach(engine: TorrentEngine) {
        self.engine = engine
    }

    func install(on server: HttpServer) {
        server["/transmission/rpc"] = { [weak self] req in
            guard let self else { return .internalServerError }

            // If engine not attached yet, fail cleanly
            guard self.engine != nil else {
                return self.serviceUnavailable("Transmission RPC not installed yet (TorrentEngine not attached).")
            }

            // 1) BASIC AUTH (first)
            let settings = AppSettings.shared
            let requiredUser = settings.rpcUsername
            let requiredPass = settings.rpcPassword

            if !requiredUser.isEmpty || !requiredPass.isEmpty {
                guard let creds = self.basicAuthCredentials(from: req),
                      creds.user == requiredUser,
                      creds.pass == requiredPass else {
                    return self.unauthorized()
                }
            }

            // 2) X-Transmission-Session-Id handshake
            let clientSessionID = req.headers["x-transmission-session-id"]
                ?? req.headers["X-Transmission-Session-Id"]

            if clientSessionID != self.transmissionSessionID {
                self.transmissionSessionID = UUID().uuidString
                return HttpResponse.raw(
                    409,
                    "Conflict",
                    ["X-Transmission-Session-Id": self.transmissionSessionID],
                    nil
                )
            }

            // 3) Parse JSON RPC body
            let bodyBytes = req.body ?? []
            let bodyData = Data(bodyBytes)
            guard
                let obj = try? JSONSerialization.jsonObject(with: bodyData, options: []),
                let json = obj as? [String: Any],
                let method = json["method"] as? String
            else {
                return .badRequest(.text("Invalid JSON"))
            }

            switch method {
            case "session-get":
                return self.handleSessionGet()
            case "torrent-get":
                return self.handleTorrentGet(json)
            case "torrent-start":
                return self.handleTorrentStart(json)
            case "torrent-stop":
                return self.handleTorrentStop(json)
            case "torrent-add":
                return self.handleTorrentAdd(json)
            default:
                return self.ok(arguments: [:]) // be permissive for now
            }
        }
    }

    // MARK: - Handlers

    private func handleSessionGet() -> HttpResponse {
        let downloadDir = AppSettings.shared.downloadURL()?.path ?? ""
        // Minimal set Radarr/Sonarr commonly expects
        return ok(arguments: [
            "version": "4.0.0",                // Transmission-ish
            "rpc-version": 15,
            "rpc-version-minimum": 1,
            "download-dir": downloadDir,
            "session-id": transmissionSessionID
        ])
    }

    private func handleTorrentGet(_ json: [String: Any]) -> HttpResponse {
        guard let engine else { return self.serviceUnavailable("Engine missing") }

        // Transmission expects: { arguments: { torrents: [...] }, result: "success" }
        let torrents: [[String: Any]] = engine.torrents.map { t in
            [
                "id": t.coreIndex,
                "hashString": t.id,
                "name": t.name,
                "percentDone": t.progress,
                "rateDownload": t.downBps,
                "rateUpload": t.upBps,
                "peersConnected": t.peers,
                "peersGettingFromUs": 0,
                "peersSendingToUs": 0,
                "isFinished": t.progress >= 0.999,
                "isStalled": false,
                "status": t.isPaused ? 0 : 4 // 0=stopped, 4=downloading (good enough)
            ]
        }

        return ok(arguments: ["torrents": torrents])
    }

    private func handleTorrentStart(_ json: [String: Any]) -> HttpResponse {
        guard let engine else { return self.serviceUnavailable("Engine missing") }
        for id in idsFrom(json: json) {
            if let t = engine.torrents.first(where: { $0.coreIndex == id }) {
                engine.resumeTorrent(id: t.id)
            }
        }
        return ok(arguments: [:])
    }

    private func handleTorrentStop(_ json: [String: Any]) -> HttpResponse {
        guard let engine else { return self.serviceUnavailable("Engine missing") }
        for id in idsFrom(json: json) {
            if let t = engine.torrents.first(where: { $0.coreIndex == id }) {
                engine.pauseTorrent(id: t.id)
            }
        }
        return ok(arguments: [:])
    }

    // MARK: - Helpers

    private func ok(arguments: [String: Any]) -> HttpResponse {
        let payload: [String: Any] = [
            "result": "success",
            "arguments": arguments
        ]
        return .ok(.json(payload))
    }

    private func unauthorized() -> HttpResponse {
        return HttpResponse.raw(
            401,
            "Unauthorized",
            ["WWW-Authenticate": "Basic realm=\"swiftTorrent\""],
            nil
        )
    }

    private func basicAuthCredentials(from req: HttpRequest) -> (user: String, pass: String)? {
        guard let header = req.headers["authorization"] ?? req.headers["Authorization"] else { return nil }
        guard header.lowercased().hasPrefix("basic ") else { return nil }

        let b64 = header.dropFirst(6)
        guard let data = Data(base64Encoded: String(b64)) else { return nil }
        guard let decoded = String(data: data, encoding: .utf8) else { return nil }

        // user:pass
        let parts = decoded.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private func idsFrom(json: [String: Any]) -> [Int] {
        guard
            let args = json["arguments"] as? [String: Any],
            let ids = args["ids"] as? [Any]
        else { return [] }

        return ids.compactMap { $0 as? Int }
    }
    
    private func serviceUnavailable(_ message: String) -> HttpResponse {
        HttpResponse.raw(
            503,
            "Service Unavailable",
            ["Content-Type": "text/plain; charset=utf-8"],
            { writer in
                try writer.write([UInt8](message.utf8))
            }
        )
    }
    private func handleTorrentAdd(_ json: [String: Any]) -> HttpResponse {
        guard let engine else { return serviceUnavailable("Engine missing") }

        guard let args = json["arguments"] as? [String: Any] else {
            return .badRequest(.text("Missing arguments"))
        }

        // Helpful debug
        print("[RPC] torrent-add args:", args.keys.sorted())

        // Transmission: may send either `download-dir` OR rely on session download-dir
        let sessionDownloadDir = AppSettings.shared.downloadURL()?.path ?? ""

        let downloadDir = (args["download-dir"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let savePath = (downloadDir?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (downloadDir ?? "") : sessionDownloadDir

        // Ensure the folder exists
        do {
            try FileManager.default.createDirectory(atPath: savePath, withIntermediateDirectories: true)
        } catch {
            return .badRequest(.text("Cannot create download dir: \(error.localizedDescription)"))
        }

        // Derive a category if Radarr used /downloads/Movie style
        let base = sessionDownloadDir.isEmpty ? "" : (sessionDownloadDir.hasSuffix("/") ? String(sessionDownloadDir.dropLast()) : sessionDownloadDir)
        let category: String? = savePath.hasPrefix(base) ? URL(fileURLWithPath: savePath).lastPathComponent.lowercased() : nil

        // 1) Magnet path (most common)
        if let filename = (args["filename"] as? String),
           filename.lowercased().hasPrefix("magnet:") {

            if let err = engine.addMagnet(filename, savePath: savePath, category: category, persist: true) {
                return .badRequest(.text("Failed to add magnet: \(err)"))
            }

            return ok(arguments: [
                "torrent-added": [
                    "id": engine.torrents.last?.coreIndex ?? 0,
                    "hashString": engine.torrents.last?.id ?? "",
                    "name": engine.torrents.last?.name ?? ""
                ]
            ])
        }

        // 2) .torrent metainfo (base64) — Radarr can do this too
        if let metainfoB64 = args["metainfo"] as? String,
           let data = Data(base64Encoded: metainfoB64) {

            // If you don't yet support adding from .torrent data in TorrentCore,
            // return a clear error so we can implement the missing TorrentCore function next.
            return .badRequest(.text("metainfo (.torrent) not supported yet by swiftTorrent (need TorrentCore add-torrent-data)."))
        }

        // 3) Non-magnet "filename" (URL/path) — not supported yet
        if let filename = args["filename"] as? String {
            return .badRequest(.text("torrent-add filename not supported (not a magnet): \(filename.prefix(120))"))
        }

        return .badRequest(.text("torrent-add missing filename/metainfo"))
    }
}

