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
            RunDiagnostics.shared.log("TorrentEngine attached; Transmission RPC is now live at /transmission/rpc")
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
            RunDiagnostics.shared.log("WebUI running at http://127.0.0.1:\(p)")
            RunDiagnostics.shared.log("Transmission RPC available at http://127.0.0.1:\(p)/transmission/rpc")
        } catch {
            currentPort = nil
            // Swift's default NSError bridge drops Swifter.SocketError's
            // associated errno text (for example, "Address already in use").
            // Keep the reflected error so ARR callback failures are diagnosable.
            RunDiagnostics.shared.log(
                "Failed to start web server on port \(p): \(String(reflecting: error)); description=\(error.localizedDescription)",
                level: "ERROR"
            )
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

        server["/api/arr/grab"] = { [weak self] req in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handleArrGrab(req) }
        }

        server["/api/arr/diagnostics"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            return DispatchQueue.main.sync { self.handleArrDiagnostics() }
        }

        server["/api/diagnostics/last-run"] = { _ in
            DispatchQueue.main.sync {
                .ok(.json(RunDiagnostics.shared.diagnosticsSnapshot(logLines: 200)))
            }
        }

        server["/api/diagnostics/logs"] = { req in
            DispatchQueue.main.sync {
                let requested = self.queryIntValue(named: "lines", in: req) ?? 200
                return .ok(.json(RunDiagnostics.shared.diagnosticsSnapshot(logLines: requested)))
            }
        }

        rpc.install(on: server)
    }

    private func configureStaticWebUI() {
        guard let webRoot = Bundle.main.resourceURL?.appendingPathComponent("WebUI") else {
            RunDiagnostics.shared.log("WebUI folder not found in bundle resources", level: "ERROR")
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
                "progress": file.progress,
                "isWanted": file.isWanted,
                "isSkipped": file.isSkipped,
                "isPrioritized": file.isPrioritized
            ] as [String: Any]
        }

        let overrideHint = engine.currentMetadataOverride(for: id)
        let payload: [String: Any] = [
            "torrent": torrentSummary(torrent: torrent, metadata: metadata),
            "metadata": metadataPayload(for: id, metadata: metadata) as Any,
            "metadataLookupState": lookupStateValue(engine.metadataLookupStateByID[id] ?? .idle),
            "metadataLookupError": engine.metadataLookupErrorByID[id] as Any,
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
        case "boost":
            engine.toggleBoost(torrentID: id)
        case "setCategory":
            let category = (body["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            engine.setCategory(category?.isEmpty == false ? category : nil, for: id)
        case "setFileWanted":
            guard let fileID = body["fileID"] as? Int,
                  let wanted = body["wanted"] as? Bool else {
                return .badRequest(.text("setFileWanted requires fileID and wanted"))
            }
            engine.setFileWanted(wanted, torrentID: id, fileID: fileID)
        case "setFilePriority":
            guard let fileID = body["fileID"] as? Int,
                  let prioritized = body["prioritized"] as? Bool else {
                return .badRequest(.text("setFilePriority requires fileID and prioritized"))
            }
            engine.setFilePrioritized(prioritized, torrentID: id, fileID: fileID)
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

    private func handleArrGrab(_ req: HttpRequest) -> HttpResponse {
        let fields = requestFields(req)

        guard let rawDownloadID = firstValue(in: fields, keys: [
            "downloadId",
            "download_id",
            "downloadid",
            "radarr_download_id",
            "sonarr_download_id",
            "tsuname_download_id",
            "infoHash",
            "info_hash",
            "hash"
        ])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawDownloadID.isEmpty else {
            return .badRequest(.text("Missing downloadId"))
        }

        // ARR download IDs normally equal the torrent info hash, but accepting a
        // magnet URI here also makes the hint key line up with TorrentStore.
        let key = MagnetKeyExtractor.key(from: rawDownloadID) ?? ArrMetadataStore.normalizedKey(rawDownloadID)
        let source = arrSource(from: fields)
        let type = arrType(from: fields, source: source)
        let title = firstValue(in: fields, keys: [
            "radarr_movie_title",
            "sonarr_series_title",
            "movie.title",
            "series.title",
            "movieTitle",
            "seriesTitle",
            "movie_title",
            "series_title",
            "mediaTitle",
            "media_title",
            "tsuname_title",
            "title"
        ])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !title.isEmpty else {
            return .badRequest(.text("Missing title"))
        }

        let hint = ArrMetadataHint(
            key: key,
            source: source,
            arrID: firstIntValue(in: fields, keys: [
                "radarr_movie_id",
                "sonarr_series_id",
                "movie.id",
                "series.id",
                "movieId",
                "seriesId",
                "movie_id",
                "series_id",
                "mediaId",
                "media_id",
                "tsuname_media_id"
            ]),
            type: type,
            title: title,
            year: firstIntValue(in: fields, keys: [
                "year",
                "movie.year",
                "series.year",
                "movieYear",
                "seriesYear",
                "radarr_movie_year",
                "sonarr_series_year"
            ]),
            imdbID: firstValue(in: fields, keys: [
                "imdbId",
                "imdb_id",
                "movie.imdbId",
                "series.imdbId",
                "radarr_movie_imdbid",
                "sonarr_series_imdbid"
            ]),
            tmdbID: firstIntValue(in: fields, keys: [
                "tmdbId",
                "tmdb_id",
                "movie.tmdbId",
                "series.tmdbId",
                "radarr_movie_tmdbid",
                "sonarr_series_tmdbid"
            ]),
            tvdbID: firstIntValue(in: fields, keys: [
                "tvdbId",
                "tvdb_id",
                "series.tvdbId",
                "sonarr_series_tvdbid"
            ]),
            tvmazeID: firstIntValue(in: fields, keys: [
                "tvmazeId",
                "tvmaze_id",
                "series.tvmazeId",
                "sonarr_series_tvmazeid"
            ]),
            traktID: firstIntValue(in: fields, keys: [
                "traktId",
                "trakt_id",
                "radarr_movie_traktid",
                "sonarr_series_traktid"
            ]),
            scope: firstValue(in: fields, keys: [
                "scope",
                "requestScope",
                "request_scope",
                "tsuname_scope",
                "eventType"
            ]),
            seasons: intListValue(in: fields, keys: [
                "seasons",
                "season",
                "seasonNumber",
                "season_number",
                "tsuname_seasons"
            ]),
            episodes: arrEpisodeRefs(from: fields),
            releaseTitle: firstValue(in: fields, keys: [
                "releaseTitle",
                "release_title",
                "release.releaseTitle",
                "release.title",
                "tsuname_release_title"
            ]),
            updatedAt: Date()
        )

        ArrMetadataStore.upsert(hint)
        RunDiagnostics.shared.log(
            "[ARR] Grab hint received source=\(source.rawValue) title=\(title) key=\(key) type=\(type) IDs(imdb=\(hint.imdbID ?? "-"), tmdb=\(hint.tmdbID.map(String.init) ?? "-"), tvdb=\(hint.tvdbID.map(String.init) ?? "-"), tvmaze=\(hint.tvmazeID.map(String.init) ?? "-"), trakt=\(hint.traktID.map(String.init) ?? "-")) release=\(hint.releaseTitle ?? "-") episodes=\(hint.episodes.map { "S\($0.season)E\($0.episode)" }.joined(separator: ","))"
        )
        if let mediaType = hint.mediaType {
            TorrentStore.assignCategoryIfMissing(
                key: key,
                category: mediaType == .show ? "tv" : "movie"
            )
        }

        if let engine {
            let matchingIDs = engine.torrents
                .map(\.id)
                .filter { stableKey(forLiveTorrentID: $0) == key || ArrMetadataStore.normalizedKey($0) == key }
            for liveID in matchingIDs {
                if let torrent = engine.torrents.first(where: { $0.id == liveID }) {
                    engine.refreshMetadata(for: torrent)
                }
            }
            if matchingIDs.isEmpty {
                RunDiagnostics.shared.log("[ARR] Grab hint saved for \(key); no current torrent has this info hash. Metadata will use it if a later torrent matches.", level: "WARN")
            } else {
                RunDiagnostics.shared.log("[ARR] Grab hint matched \(matchingIDs.count) current torrent(s) for \(key)")
            }
        } else {
            RunDiagnostics.shared.log("[ARR] Grab hint saved for \(key), but the torrent engine is not attached yet.", level: "WARN")
        }

        return ok([
            "success": true,
            "key": key,
            "title": title,
            "type": type,
            "source": hint.source.rawValue,
            "scope": hint.scope as Any,
            "seasons": hint.seasons,
            "episodes": hint.episodes.map { ["season": $0.season, "episode": $0.episode] }
        ])
    }

    private func handleArrDiagnostics() -> HttpResponse {
        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = ArrMetadataStore.all()
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(30)
            .map { hint in
                let matchingTorrents = (engine?.torrents ?? []).filter {
                    stableKey(for: $0) == ArrMetadataStore.normalizedKey(hint.key)
                        || ArrMetadataStore.normalizedKey($0.id) == ArrMetadataStore.normalizedKey(hint.key)
                }
                return [
                    "receivedAt": formatter.string(from: hint.updatedAt),
                    "source": hint.source.rawValue,
                    "title": hint.title,
                    "type": hint.type,
                    "year": hint.year.map { $0 as Any } ?? NSNull(),
                    "downloadKey": hint.key,
                    "ids": [
                        "imdb": hint.imdbID.map { $0 as Any } ?? NSNull(),
                        "tmdb": hint.tmdbID.map { $0 as Any } ?? NSNull(),
                        "tvdb": hint.tvdbID.map { $0 as Any } ?? NSNull(),
                        "tvmaze": hint.tvmazeID.map { $0 as Any } ?? NSNull(),
                        "trakt": hint.traktID.map { $0 as Any } ?? NSNull()
                    ],
                    "releaseTitle": hint.releaseTitle.map { $0 as Any } ?? NSNull(),
                    "episodes": hint.episodes.map { ["season": $0.season, "episode": $0.episode] },
                    "matchedTorrentCount": matchingTorrents.count,
                    "matchedTorrents": matchingTorrents.map { ["id": $0.id, "name": $0.name] }
                ]
            }
        return ok(["count": entries.count, "hints": entries])
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
            "totalWanted": torrent.totalWanted,
            "totalWantedDone": torrent.totalWantedDone,
            "downloadedTotal": torrent.downloadedTotal,
            "uploadedTotal": torrent.uploadedTotal,
            "peers": torrent.peers,
            "seeds": torrent.seeds,
            "state": torrent.state,
            "stateLabel": stateLabel(torrent.state, isPaused: torrent.isPaused, isSeeding: torrent.isSeeding),
            "isPaused": torrent.isPaused,
            "isSeeding": torrent.isSeeding,
            "isBoosted": engine?.isBoosted(torrentID: torrent.id) ?? false,
            "isQueued": engine?.isQueued(torrentID: torrent.id) ?? false,
            "category": category as Any,
            "categoryTitle": AppSettings.shared.categoryDefinition(for: category)?.title as Any,
            "metadata": metadataPayload(for: torrent.id, metadata: metadata) as Any,
            "lookupState": lookupStateValue(engine?.metadataLookupStateByID[torrent.id] ?? .idle),
            "lookupError": engine?.metadataLookupErrorByID[torrent.id] as Any
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
            "sources": Array(metadata.sources).sorted(),
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

    private func parseFormBody(_ bytes: [UInt8]) -> [String: String] {
        guard !bytes.isEmpty,
              let text = String(bytes: bytes, encoding: .utf8),
              let components = URLComponents(string: "http://localhost?\(text)") else {
            return [:]
        }

        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value
        }
        return result
    }

    private func requestFields(_ req: HttpRequest) -> [String: String] {
        var fields = Dictionary(uniqueKeysWithValues: req.queryParams.map { ($0.0, $0.1) })

        if let json = parseJSONBody(req.body) {
            flattenJSONFields(json, prefix: nil, into: &fields)
        }

        for (key, value) in parseFormBody(req.body) {
            fields[key] = value
        }

        return fields
    }

    private func flattenJSONFields(_ object: [String: Any], prefix: String?, into fields: inout [String: String]) {
        for (key, value) in object {
            let path = prefix.map { "\($0).\(key)" } ?? key
            if let nested = value as? [String: Any] {
                flattenJSONFields(nested, prefix: path, into: &fields)
            } else if let string = value as? String {
                fields[path] = string
                if prefix == nil { fields[key] = string }
            } else if let number = value as? NSNumber {
                fields[path] = number.stringValue
                if prefix == nil { fields[key] = number.stringValue }
            } else if JSONSerialization.isValidJSONObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: value),
                      let string = String(data: data, encoding: .utf8) {
                fields[path] = string
                if prefix == nil { fields[key] = string }
            }
        }
    }

    private func firstValue(in fields: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key], !value.isEmpty {
                return value
            }
            if let match = fields.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }),
               !match.value.isEmpty {
                return match.value
            }
        }
        return nil
    }

    private func firstIntValue(in fields: [String: String], keys: [String]) -> Int? {
        for key in keys {
            if let value = fields[key], let intValue = Int(value) {
                return intValue
            }
            if let match = fields.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }),
               let intValue = Int(match.value) {
                return intValue
            }
        }
        return nil
    }

    private func intListValue(in fields: [String: String], keys: [String]) -> [Int] {
        for key in keys {
            guard let raw = firstValue(in: fields, keys: [key]) else { continue }
            let ints = ints(from: raw)
            if !ints.isEmpty { return Array(Set(ints)).sorted() }
        }
        return []
    }

    private func ints(from raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.compactMap { value in
                if let number = value as? NSNumber { return number.intValue }
                if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
                return nil
            }
        }

        return trimmed
            .split { ",;| \n\t".contains($0) }
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func episodeRefsValue(in fields: [String: String], keys: [String]) -> [ArrMetadataHint.EpisodeRef] {
        for key in keys {
            guard let raw = firstValue(in: fields, keys: [key]) else { continue }
            let episodes = episodeRefs(from: raw)
            if !episodes.isEmpty {
                return Array(Set(episodes)).sorted {
                    $0.season == $1.season ? $0.episode < $1.episode : $0.season < $1.season
                }
            }
        }
        return []
    }

    private func sonarrEpisodeRefs(from fields: [String: String]) -> [ArrMetadataHint.EpisodeRef] {
        guard let season = firstIntValue(in: fields, keys: ["seasonNumber", "season_number", "sonarr_release_seasonnumber"]),
              let rawEpisodes = firstValue(in: fields, keys: ["episodeNumbers", "episode_numbers", "sonarr_release_episodenumbers"]) else {
            return []
        }
        return Array(Set(rawEpisodes.split { ",;| \n\t".contains($0) }.compactMap { Int($0) }.map {
            ArrMetadataHint.EpisodeRef(season: season, episode: $0)
        })).sorted { $0.episode < $1.episode }
    }

    private func arrEpisodeRefs(from fields: [String: String]) -> [ArrMetadataHint.EpisodeRef] {
        let refs = episodeRefsValue(in: fields, keys: [
            "episodes", "episode", "episodeRefs", "episode_refs", "tsuname_episodes"
        ])
        return refs.isEmpty ? sonarrEpisodeRefs(from: fields) : refs
    }

    private func episodeRefs(from raw: String) -> [ArrMetadataHint.EpisodeRef] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.compactMap { value in
                if let dict = value as? [String: Any] {
                    let season = intValue(from: dict, keys: ["season", "seasonNumber", "season_number"])
                    let episode = intValue(from: dict, keys: ["episode", "episodeNumber", "episode_number"])
                    if let season, let episode { return ArrMetadataHint.EpisodeRef(season: season, episode: episode) }
                }
                if let string = value as? String {
                    return episodeRef(fromToken: string)
                }
                return nil
            }
        }

        return trimmed
            .split { ",;| \n\t".contains($0) }
            .compactMap { episodeRef(fromToken: String($0)) }
    }

    private func intValue(from dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber { return number.intValue }
            if let string = dict[key] as? String, let value = Int(string) { return value }
            if let match = dict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                if let number = match.value as? NSNumber { return number.intValue }
                if let string = match.value as? String, let value = Int(string) { return value }
            }
        }
        return nil
    }

    private func episodeRef(fromToken token: String) -> ArrMetadataHint.EpisodeRef? {
        let pattern = #"(?i)(?:s)?(\d{1,2})\s*(?:x|e)\s*(\d{1,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              match.numberOfRanges >= 3,
              let seasonRange = Range(match.range(at: 1), in: token),
              let episodeRange = Range(match.range(at: 2), in: token),
              let season = Int(token[seasonRange]),
              let episode = Int(token[episodeRange]) else {
            return nil
        }
        return ArrMetadataHint.EpisodeRef(season: season, episode: episode)
    }

    private func arrSource(from fields: [String: String]) -> ArrMetadataHint.Source {
        let keys = fields.keys.map { $0.lowercased() }
        if keys.contains(where: { $0.hasPrefix("radarr_") || $0.hasPrefix("movie.") }) || firstValue(in: fields, keys: ["source"])?.lowercased() == "radarr" {
            return .radarr
        }
        if keys.contains(where: { $0.hasPrefix("sonarr_") || $0.hasPrefix("series.") }) || firstValue(in: fields, keys: ["source"])?.lowercased() == "sonarr" {
            return .sonarr
        }
        if fields.keys.contains(where: { $0.hasPrefix("tsuname_") }) || firstValue(in: fields, keys: ["source"])?.lowercased() == "tsuname" {
            return .tsuname
        }
        return .unknown
    }

    private func arrType(from fields: [String: String], source: ArrMetadataHint.Source) -> String {
        if let explicit = firstValue(in: fields, keys: ["type", "mediaType", "media_type"])?.lowercased() {
            if explicit.contains("show") || explicit.contains("series") || explicit == "tv" { return "show" }
            if explicit.contains("movie") { return "movie" }
        }

        switch source {
        case .radarr:
            return "movie"
        case .sonarr, .tsuname:
            return "show"
        case .unknown:
            return "movie"
        }
    }

    private func queryValue(named name: String, in request: HttpRequest) -> String? {
        request.queryParams.first(where: { $0.0 == name })?.1
    }

    private func queryIntValue(named name: String, in request: HttpRequest) -> Int? {
        guard let raw = queryValue(named: name, in: request) else { return nil }
        return Int(raw)
    }

    private func stableKey(for torrent: TorrentRow) -> String {
        stableKey(forLiveTorrentID: torrent.id)
    }

    private func stableKey(forLiveTorrentID id: String) -> String {
        MagnetKeyExtractor.key(from: id) ?? id
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
