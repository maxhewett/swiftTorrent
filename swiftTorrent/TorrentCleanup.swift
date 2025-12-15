//
//  TorrentCleanup.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

enum TorrentCleanup {

    enum Mode { case move, copy }
    enum Collision { case rename, skip, overwrite }

    struct CleanupSettings {
        var moviesRoot: URL
        var tvRoot: URL
        var mode: Mode = .move
        var collision: Collision = .rename
    }

    enum CleanupError: Error, LocalizedError {
        case noFiles
        case noDestination
        case invalidRelativePath(String)

        var errorDescription: String? {
            switch self {
            case .noFiles: return "No torrent files available to clean up."
            case .noDestination: return "No destination folder could be determined."
            case .invalidRelativePath(let p): return "Invalid torrent file path: \(p)"
            }
        }
    }

    /// Move/copy ONLY the files that belong to this torrent.
    ///
    /// - saveRoot: the libtorrent save path (often ~/Downloads)
    /// - filePaths: file paths from libtorrent (usually relative to saveRoot)
    /// - If files share a single top-level folder, we move the *contents* of that folder.
    @discardableResult
    static func run(
        torrentID: String,
        saveRoot: URL,
        filePaths: [String],
        meta: MediaMetadata,
        parsedSeason: Int?,
        category: String?,
        settings: CleanupSettings
    ) throws -> URL {

        let rels = filePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rels.isEmpty else { throw CleanupError.noFiles }

        // Determine destination folder
        let destBase: URL
        switch meta.type {
        case .movie:
            destBase = settings.moviesRoot
        case .show:
            destBase = settings.tvRoot
        }

        let titleFolder = sanitizedTitleFolder(meta: meta) // "Friends (1994)" etc.
        var dest = destBase.appendingPathComponent(titleFolder, isDirectory: true)

        if meta.type == .show, let season = parsedSeason {
            dest = dest.appendingPathComponent("Season \(String(format: "%02d", season))", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Identify if the torrent uses a single top-level folder like "Dont.Look.Up.../file.mkv"
        let topLevels = Set(rels.compactMap { firstPathComponent(of: $0) })
        let hasSingleTopLevelFolder = (topLevels.count == 1) && rels.allSatisfy { $0.contains("/") || $0.contains("\\") }
        let singleTop = hasSingleTopLevelFolder ? topLevels.first : nil

        // We will move either:
        // - contents of the single top folder (strip it off), OR
        // - each file directly under saveRoot preserving relative layout
        let fm = FileManager.default
        var movedAnything = false

        for rel in rels {
            let normRel = normalizeRelative(rel)
            guard !normRel.isEmpty else { continue }

            let src = saveRoot.appendingPathComponent(normRel, isDirectory: false)
            guard fm.fileExists(atPath: src.path) else {
                continue // not present yet, skip
            }

            let destRel: String
            if let top = singleTop {
                // Strip "TopFolder/" so we don't nest the release folder
                destRel = stripLeadingComponent(normRel, topComponent: top)
            } else {
                destRel = normRel
            }

            let dst = dest.appendingPathComponent(destRel, isDirectory: false)

            // Ensure parent folder exists
            let parent = dst.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)

            let finalDst = try resolveCollision(dst, collision: settings.collision)

            if settings.mode == .copy {
                try copyItem(at: src, to: finalDst)
            } else {
                try moveItem(at: src, to: finalDst)
            }

            movedAnything = true
        }

        // Remove now-empty single top-level folder (release folder) if we stripped it
        if movedAnything, let top = singleTop {
            let releaseFolder = saveRoot.appendingPathComponent(top, isDirectory: true)
            removeFolderIfEmpty(releaseFolder)
        }

        return dest
    }

    // MARK: - Helpers

    private static func sanitizedTitleFolder(meta: MediaMetadata) -> String {
        let base = meta.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let y = meta.year {
            return sanitizeFilename("\(base) (\(y))")
        }
        return sanitizeFilename(base)
    }

    private static func sanitizeFilename(_ s: String) -> String {
        // keep it simple and filesystem-safe
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var out = s.components(separatedBy: forbidden).joined(separator: " ")
        out = out.replacingOccurrences(of: "  ", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeRelative(_ p: String) -> String {
        // libtorrent paths are typically forward slashes; handle backslashes too
        var s = p.replacingOccurrences(of: "\\", with: "/")
        // avoid absolute
        while s.hasPrefix("/") { s.removeFirst() }
        // collapse ./ segments
        while s.hasPrefix("./") { s.removeFirst(2) }
        return s
    }

    private static func firstPathComponent(of p: String) -> String? {
        let s = normalizeRelative(p)
        let comps = s.split(separator: "/", omittingEmptySubsequences: true)
        return comps.first.map(String.init)
    }

    private static func stripLeadingComponent(_ rel: String, topComponent: String) -> String {
        let s = normalizeRelative(rel)
        if s == topComponent { return "" }
        let prefix = topComponent + "/"
        if s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count))
        }
        return s
    }

    private static func resolveCollision(_ dst: URL, collision: Collision) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dst.path) { return dst }

        switch collision {
        case .skip:
            // return something that causes a no-op by pointing to same path, caller can decide
            return dst

        case .overwrite:
            try? fm.removeItem(at: dst)
            return dst

        case .rename:
            let base = dst.deletingPathExtension().lastPathComponent
            let ext = dst.pathExtension
            let dir = dst.deletingLastPathComponent()

            var i = 2
            while true {
                let name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
                let candidate = dir.appendingPathComponent(name)
                if !fm.fileExists(atPath: candidate.path) { return candidate }
                i += 1
            }
        }
    }

    private static func moveItem(at src: URL, to dst: URL) throws {
        let fm = FileManager.default
        // If destination exists and collision was "skip", just return
        if fm.fileExists(atPath: dst.path) { return }
        try fm.moveItem(at: src, to: dst)
    }

    private static func copyItem(at src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { return }
        try fm.copyItem(at: src, to: dst)
    }

    private static func removeFolderIfEmpty(_ folder: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        if items.isEmpty {
            try? fm.removeItem(at: folder)
        }
    }
}
