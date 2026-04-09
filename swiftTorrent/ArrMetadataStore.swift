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
        case unknown
    }

    let key: String
    let source: Source
    let type: String
    let title: String
    let year: Int?
    let imdbID: String?
    let tmdbID: Int?
    let tvdbID: Int?
    let traktID: Int?
    let updatedAt: Date

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
