//
//  ArrMetadataStore.swift
//  swiftTorrent
//
//  Created by Codex on 4/03/2026.
//

import Foundation

struct ArrMetadataHint: Codable, Hashable {
    enum Source: String, Codable {
        case radarr
        case sonarr
        case tsuname
        case unknown
    }

    struct EpisodeRef: Codable, Hashable {
        let season: Int
        let episode: Int
    }

    let key: String
    let source: Source
    let arrID: Int?
    let type: String
    let title: String
    let year: Int?
    let imdbID: String?
    let tmdbID: Int?
    let tvdbID: Int?
    let traktID: Int?
    let scope: String?
    let seasons: [Int]
    let episodes: [EpisodeRef]
    let releaseTitle: String?
    let updatedAt: Date

    init(
        key: String,
        source: Source,
        arrID: Int?,
        type: String,
        title: String,
        year: Int?,
        imdbID: String?,
        tmdbID: Int?,
        tvdbID: Int?,
        traktID: Int?,
        scope: String? = nil,
        seasons: [Int] = [],
        episodes: [EpisodeRef] = [],
        releaseTitle: String? = nil,
        updatedAt: Date
    ) {
        self.key = key
        self.source = source
        self.arrID = arrID
        self.type = type
        self.title = title
        self.year = year
        self.imdbID = imdbID
        self.tmdbID = tmdbID
        self.tvdbID = tvdbID
        self.traktID = traktID
        self.scope = scope
        self.seasons = seasons
        self.episodes = episodes
        self.releaseTitle = releaseTitle
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        source = (try? container.decode(Source.self, forKey: .source)) ?? .unknown
        arrID = try container.decodeIfPresent(Int.self, forKey: .arrID)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        imdbID = try container.decodeIfPresent(String.self, forKey: .imdbID)
        tmdbID = try container.decodeIfPresent(Int.self, forKey: .tmdbID)
        tvdbID = try container.decodeIfPresent(Int.self, forKey: .tvdbID)
        traktID = try container.decodeIfPresent(Int.self, forKey: .traktID)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        seasons = try container.decodeIfPresent([Int].self, forKey: .seasons) ?? []
        episodes = try container.decodeIfPresent([EpisodeRef].self, forKey: .episodes) ?? []
        releaseTitle = try container.decodeIfPresent(String.self, forKey: .releaseTitle)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var mediaType: MediaMetadata.MediaType? {
        switch type.lowercased() {
        case "movie":
            return .movie
        case "show", "series", "tv":
            return .show
        default:
            return nil
        }
    }
}

enum ArrMetadataStore {
    private static let fileName = "arr-metadata.json"

    static func upsert(_ hint: ArrMetadataHint) {
        var items = loadAll()
        items[normalizedKey(hint.key)] = hint
        saveAll(items)
    }

    static func find(key: String) -> ArrMetadataHint? {
        loadAll()[normalizedKey(key)]
    }

    static func remove(key: String) {
        var items = loadAll()
        items.removeValue(forKey: normalizedKey(key))
        saveAll(items)
    }

    static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func loadAll() -> [String: ArrMetadataHint] {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ArrMetadataHint].self, from: data)) ?? [:]
    }

    private static func saveAll(_ items: [String: ArrMetadataHint]) {
        let url = storeURL()
        do {
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            RunDiagnostics.shared.log("ArrMetadataStore save failed: \(error.localizedDescription)", level: "ERROR")
        }
    }

    private static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("swiftTorrent", isDirectory: true)
        return dir.appendingPathComponent(fileName)
    }
}
