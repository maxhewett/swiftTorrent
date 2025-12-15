//
//  AppSettings.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: Keys
    private enum K {
        static let autoCleanupEnabled = "swiftTorrent.settings.autoCleanupEnabled"
        static let moviesBookmark = "swiftTorrent.settings.moviesBookmark"
        static let tvBookmark = "swiftTorrent.settings.tvBookmark"
        static let cleanedKeys = "swiftTorrent.settings.cleanedTorrentKeys"
    }

    @Published var autoCleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanupEnabled, forKey: K.autoCleanupEnabled) }
    }

    // Security-scoped bookmarks (Data) for destination roots
    @Published var moviesBookmarkData: Data? {
        didSet { UserDefaults.standard.set(moviesBookmarkData, forKey: K.moviesBookmark) }
    }

    @Published var tvBookmarkData: Data? {
        didSet { UserDefaults.standard.set(tvBookmarkData, forKey: K.tvBookmark) }
    }

    // "Already cleaned" tracking (by torrent key/id)
    @Published private(set) var cleanedTorrentKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(cleanedTorrentKeys), forKey: K.cleanedKeys) }
    }

    private init() {
        self.autoCleanupEnabled = UserDefaults.standard.bool(forKey: K.autoCleanupEnabled)
        self.moviesBookmarkData = UserDefaults.standard.data(forKey: K.moviesBookmark)
        self.tvBookmarkData = UserDefaults.standard.data(forKey: K.tvBookmark)
        let arr = UserDefaults.standard.stringArray(forKey: K.cleanedKeys) ?? []
        self.cleanedTorrentKeys = Set(arr)
    }

    func markCleaned(_ key: String) {
        cleanedTorrentKeys.insert(key)
    }

    func unmarkCleaned(_ key: String) {
        cleanedTorrentKeys.remove(key)
    }

    func resetCleaned() {
        cleanedTorrentKeys = []
    }

    // MARK: Bookmark helpers

    func setMoviesURL(_ url: URL) throws {
        moviesBookmarkData = try makeBookmark(for: url)
        print("Saved movies bookmark bytes:", moviesBookmarkData?.count ?? 0)
    }

    func setTVURL(_ url: URL) throws {
        tvBookmarkData = try makeBookmark(for: url)
    }

    func moviesURL() -> URL? { resolveBookmark(moviesBookmarkData) }
    func tvURL() -> URL? { resolveBookmark(tvBookmarkData) }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        if stale {
            // refresh + persist the updated bookmark
            if let refreshed = try? makeBookmark(for: url) {
                if data == moviesBookmarkData { moviesBookmarkData = refreshed }
                if data == tvBookmarkData { tvBookmarkData = refreshed }
            }
        }

        return url
    }
}
