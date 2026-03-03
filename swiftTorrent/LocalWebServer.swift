//
//  LocalWebServer.swift
//  swiftTorrent
//
//  Created by Max Hewett on 16/12/2025.
//

import AppKit
import Foundation
import Swifter

@MainActor
final class LocalWebServer {
    static let shared = LocalWebServer()

    private let server = HttpServer()
    private var isConfigured = false
    private var currentPort: in_port_t?
    private let webRevision = UUID().uuidString

    private weak var engine: TorrentEngine?
    private let rpc = TransmissionRPC()

    func attach(engine: TorrentEngine) {
        self.engine = engine
        rpc.attach(engine: engine)

        if currentPort != nil {
            print("TorrentEngine attached; Transmission RPC is now live at /transmission/rpc")
        }
    }

    func start(port: Int) {
        let p = in_port_t(clamping: port)
        if currentPort == p { return }

        stop()
        configureRoutesIfNeeded()
        configureStaticWebUI()

        do {
            try server.start(p, forceIPv4: true)
            currentPort = p
            print("WebUI running at http://127.0.0.1:\(p)")
            print("Transmission RPC available at http://127.0.0.1:\(p)/transmission/rpc")
        } catch {
            currentPort = nil
            print("Failed to start web server:", error)
        }
    }

    func stop() {
        server.stop()
        currentPort = nil
    }

    private func configureRoutesIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        server["/api/ping"] = { _ in
            .ok(.json([
                "status": "ok",
                "version": "0.0.3"
            ]))
        }

        server["/api/state"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handleState() }
        }

        server["/api/torrent"] = { [weak self] req in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handleTorrentDetail(req) }
        }

        server["/api/torrent/action"] = { [weak self] req in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handleTorrentAction(req) }
        }

        server["/api/poster"] = { [weak self] req in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handlePoster(req) }
        }

        server["/api/app-icon"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handleAppIcon() }
        }

        rpc.install(on: server)
    }

    private func configureStaticWebUI() {
        guard let webRoot = Bundle.main.resourceURL?.appendingPathComponent("WebUI") else {
            print("WebUI folder not found in bundle resources")
            return
        }

        let indexPath = webRoot.appendingPathComponent("index.html").path

        server["/"] = { _ in
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
                return .ok(.data(data, contentType: "text/html; charset=utf-8"))
            } catch {
                return .notFound
            }
        }

        // The WebUI is currently a single self-contained HTML page. Avoid a
        // catch-all static route here because Swifter would also match /api/*
        // and turn API requests into filesystem lookups that 404.
    }

    private func handleState() -> HttpResponse {
        guard let engine else { return serviceUnavailable("Torrent engine not attached") }

        let settings = AppSettings.shared
        let visibleTorrents = engine.torrents.filter { !settings.hiddenTorrentKeys.contains(stableKey(for: $0)) }

        for torrent in visibleTorrents {
            engine.enrichIfNeeded(for: torrent)
        }

        let categories = settings.categoryDefinitionsForUI.map { category in
            [
                "id": category.id,
                "title": category.title,
                "symbol": category.symbol,
                "locked": category.isLocked
            ] as [String: Any]
        }

        let torrents = visibleTorrents.map { torrent in
            let metadata = engine.mediaByTorrentID[torrent.id]
            return torrentSummary(torrent: torrent, metadata: metadata)
        }

        return ok([
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "webRevision": webRevision,
            "categories": categories,
            "torrents": torrents
        ])
    }

    private func handleTorrentDetail(_ req: HttpRequest) -> HttpResponse {
        guard let engine else { return serviceUnavailable("Torrent engine not attached") }
        guard let id = queryValue(named: "id", in: req),
              let torrent = engine.torrents.first(where: { $0.id == id }) else {
            return .notFound
        }

        engine.refreshFiles(for: id)
        engine.enrichIfNeeded(for: torrent)

        let metadata = engine.mediaByTorrentID[id]
        let files = (engine.filesByTorrentID[id] ?? []).map { file in
            [
                "id": file.id,
                "path": file.path,
                "size": file.size,
                "done": file.done,
                "progress": file.progress
            ] as [String: Any]
        }

        let overrideHint = engine.currentMetadataOverride(for: id)
        let payload: [String: Any] = [
            "torrent": torrentSummary(torrent: torrent, metadata: metadata),
            "metadata": metadataPayload(for: id, metadata: metadata) as Any,
            "metadataLookupState": lookupStateValue(engine.metadataLookupStateByID[id] ?? .idle),
            "files": files,
            "override": [
                "query": overrideHint.query as Any,
                "year": overrideHint.year as Any,
                "type": mediaTypeValue(overrideHint.type) as Any
            ]
        ]

        return ok(payload)
    }

    private func handleTorrentAction(_ req: HttpRequest) -> HttpResponse {
        guard let engine else { return serviceUnavailable("Torrent engine not attached") }
        guard let id = queryValue(named: "id", in: req),
              engine.torrents.contains(where: { $0.id == id }) else {
            return .notFound
        }

        guard let body = parseJSONBody(req.body),
              let action = body["action"] as? String else {
            return .badRequest(.text("Invalid JSON body"))
        }

        switch action {
        case "pause":
            engine.pauseTorrent(id: id)
        case "resume":
            engine.resumeTorrent(id: id)
        case "remove":
            let deleteFiles = body["deleteFiles"] as? Bool ?? false
            engine.removeTorrent(id: id, deleteFiles: deleteFiles)
        case "cleanup":
            engine.cleanupNow(torrentID: id)
        case "setCategory":
            let category = (body["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            engine.setCategory(category?.isEmpty == false ? category : nil, for: id)
        default:
            return .badRequest(.text("Unsupported action: \(action)"))
        }

        return ok(["success": true])
    }

    private func handlePoster(_ req: HttpRequest) -> HttpResponse {
        guard let id = queryValue(named: "id", in: req) else { return .notFound }

        if let localPoster = PosterCache.load(for: id),
           let data = try? Data(contentsOf: localPoster) {
            return .ok(.data(data, contentType: "image/jpeg"))
        }

        if let localPoster = engine?.mediaByTorrentID[id]?.localPosterPath,
           let data = try? Data(contentsOf: localPoster) {
            return .ok(.data(data, contentType: "image/jpeg"))
        }

        if let remotePoster = engine?.mediaByTorrentID[id]?.posterURL {
            return HttpResponse.raw(
                302,
                "Found",
                ["Location": remotePoster.absoluteString],
                nil
            )
        }

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="300" height="450" viewBox="0 0 300 450">
          <defs>
            <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#dce9f7"/>
              <stop offset="100%" stop-color="#a7bfd8"/>
            </linearGradient>
          </defs>
          <rect width="300" height="450" rx="30" fill="url(#bg)"/>
          <circle cx="150" cy="178" r="46" fill="rgba(20,37,58,0.18)"/>
          <path d="M92 304c14-39 45-58 58-58 18 0 45 16 58 58" fill="none" stroke="rgba(20,37,58,0.22)" stroke-width="18" stroke-linecap="round"/>
          <text x="150" y="372" text-anchor="middle" font-family="SF Pro Rounded, SF Pro Text, sans-serif" font-size="24" fill="rgba(20,37,58,0.55)">No Poster</text>
        </svg>
        """
        return .ok(.data(Data(svg.utf8), contentType: "image/svg+xml; charset=utf-8"))
    }

    private func handleAppIcon() -> HttpResponse {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 256, height: 256)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .notFound
        }

        return .ok(.data(pngData, contentType: "image/png"))
    }

    private func torrentSummary(torrent: TorrentRow, metadata: MediaMetadata?) -> [String: Any] {
        let category = AppSettings.shared.normalizedCategoryValue(torrent.category)
        return [
            "id": torrent.id,
            "coreIndex": torrent.coreIndex,
            "name": torrent.name,
            "progress": torrent.progress,
            "downBps": torrent.downBps,
            "upBps": torrent.upBps,
            "peers": torrent.peers,
            "seeds": torrent.seeds,
            "state": torrent.state,
            "stateLabel": stateLabel(torrent.state, isPaused: torrent.isPaused, isSeeding: torrent.isSeeding),
            "isPaused": torrent.isPaused,
            "isSeeding": torrent.isSeeding,
            "category": category as Any,
            "categoryTitle": AppSettings.shared.categoryDefinition(for: category)?.title as Any,
            "metadata": metadataPayload(for: torrent.id, metadata: metadata) as Any,
            "lookupState": lookupStateValue(engine?.metadataLookupStateByID[torrent.id] ?? .idle)
        ]
    }

    private func metadataPayload(for torrentID: String, metadata: MediaMetadata?) -> [String: Any]? {
        guard let metadata else { return nil }

        return [
            "type": mediaTypeValue(metadata.type) as Any,
            "title": metadata.title,
            "year": metadata.year as Any,
            "overview": metadata.overview as Any,
            "displaySuffix": metadata.displaySuffix as Any,
            "posterURL": "/api/poster?id=\(torrentID)&v=\(webRevision)"
        ]
    }

    private func parseJSONBody(_ bytes: [UInt8]) -> [String: Any]? {
        guard !bytes.isEmpty else { return nil }
        let data = Data(bytes)
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let json = obj as? [String: Any] else {
            return nil
        }
        return json
    }

    private func queryValue(named name: String, in request: HttpRequest) -> String? {
        request.queryParams.first(where: { $0.0 == name })?.1
    }

    private func stableKey(for torrent: TorrentRow) -> String {
        MagnetKeyExtractor.key(from: torrent.id) ?? torrent.id
    }

    private func mediaTypeValue(_ type: MediaMetadata.MediaType?) -> String? {
        switch type {
        case .movie:
            return "movie"
        case .show:
            return "show"
        case nil:
            return nil
        }
    }

    private func lookupStateValue(_ state: TorrentEngine.MetadataLookupState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .failed:
            return "failed"
        }
    }

    private func stateLabel(_ state: Int, isPaused: Bool, isSeeding: Bool) -> String {
        if isPaused { return "Paused" }
        if isSeeding { return "Seeding" }
        switch state {
        case 0: return "Queued"
        case 1: return "Checking"
        case 2: return "Downloading metadata"
        case 3: return "Downloading"
        case 4: return "Finished"
        case 5: return "Seeding"
        case 6: return "Allocating"
        case 7: return "Checking fast"
        default: return "State \(state)"
        }
    }

    private func ok(_ payload: [String: Any]) -> HttpResponse {
        .ok(.json(payload))
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
}
