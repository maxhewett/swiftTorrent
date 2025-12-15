//
//  PosterCache.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

enum PosterCache {
    static var baseURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Posters", isDirectory: true)
    }

    static func posterPath(for torrentID: String) -> URL {
        baseURL.appendingPathComponent("\(torrentID).jpg")
    }

    static func load(for torrentID: String) -> URL? {
        let url = posterPath(for: torrentID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func save(_ data: Data, torrentID: String) throws -> URL {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let url = posterPath(for: torrentID)
        try data.write(to: url, options: [.atomic])
        return url
    }
}
