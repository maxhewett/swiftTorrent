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

    private enum K {
        static let autoCleanupEnabled = "swiftTorrent.settings.autoCleanupEnabled"
        static let moviesBookmark = "swiftTorrent.settings.moviesBookmark"
        static let tvBookmark = "swiftTorrent.settings.tvBookmark"
        static let cleanedKeys = "swiftTorrent.settings.cleanedTorrentKeys"

        // NEW (for Transmission/Radarr/Sonarr friendliness)
        static let downloadBookmark = "swiftTorrent.settings.downloadBookmark"
        static let webUIPort = "swiftTorrent.settings.webUIPort"
        static let rpcUsername = "swiftTorrent.settings.rpcUsername"
        static let rpcPassword = "swiftTorrent.settings.rpcPassword"
    }

    @Published var autoCleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanupEnabled, forKey: K.autoCleanupEnabled) }
    }

    @Published var moviesBookmarkData: Data? {
        didSet {
            UserDefaults.standard.set(moviesBookmarkData, forKey: K.moviesBookmark)
            refreshResolvedURLs()
        }
    }

    @Published var tvBookmarkData: Data? {
        didSet {
            UserDefaults.standard.set(tvBookmarkData, forKey: K.tvBookmark)
            refreshResolvedURLs()
        }
    }
    
    @Published var webUIPort: Int = 8080 {
        didSet { UserDefaults.standard.set(webUIPort, forKey: K.webUIPort) }
    }

    @Published var rpcUsername: String = "" {
        didSet { UserDefaults.standard.set(rpcUsername, forKey: K.rpcUsername) }
    }

    @Published var rpcPassword: String = "" {
        didSet { UserDefaults.standard.set(rpcPassword, forKey: K.rpcPassword) }
    }

    // NEW: a “default download dir” that Radarr can see (not necessarily Movies/TV final dirs)
    @Published var downloadBookmarkData: Data? {
        didSet {
            UserDefaults.standard.set(downloadBookmarkData, forKey: K.downloadBookmark)
            refreshResolvedURLs()
        }
    }

    @Published private(set) var cleanedTorrentKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(cleanedTorrentKeys), forKey: K.cleanedKeys) }
    }

    // ✅ Cached resolved URLs so SettingsView doesn’t resolve bookmarks during layout
    @Published private(set) var resolvedMoviesURL: URL?
    @Published private(set) var resolvedTVURL: URL?
    @Published private(set) var resolvedDownloadURL: URL?

    private var isRefreshing = false

    private init() {
        self.autoCleanupEnabled = UserDefaults.standard.bool(forKey: K.autoCleanupEnabled)
        self.moviesBookmarkData = UserDefaults.standard.data(forKey: K.moviesBookmark)
        self.tvBookmarkData = UserDefaults.standard.data(forKey: K.tvBookmark)
        self.downloadBookmarkData = UserDefaults.standard.data(forKey: K.downloadBookmark)

        let arr = UserDefaults.standard.stringArray(forKey: K.cleanedKeys) ?? []
        self.cleanedTorrentKeys = Set(arr)

        self.resolvedMoviesURL = nil
        self.resolvedTVURL = nil
        self.resolvedDownloadURL = nil
        let storedPort = UserDefaults.standard.integer(forKey: K.webUIPort)
        if (1...65535).contains(storedPort) {
            self.webUIPort = storedPort
        } else {
            self.webUIPort = 8080
        }

        self.rpcUsername = UserDefaults.standard.string(forKey: K.rpcUsername) ?? ""
        self.rpcPassword = UserDefaults.standard.string(forKey: K.rpcPassword) ?? ""

        refreshResolvedURLs()
    }

    func markCleaned(_ key: String) { cleanedTorrentKeys.insert(key) }
    func unmarkCleaned(_ key: String) { cleanedTorrentKeys.remove(key) }
    func resetCleaned() { cleanedTorrentKeys = [] }

    // MARK: Bookmark setters

    func setMoviesURL(_ url: URL) throws {
        moviesBookmarkData = try makeBookmark(for: url)
    }

    func setTVURL(_ url: URL) throws {
        tvBookmarkData = try makeBookmark(for: url)
    }

    func setDownloadURL(_ url: URL) throws {
        downloadBookmarkData = try makeBookmark(for: url)
    }

    // MARK: Cached getters (use these everywhere)
    func moviesURL() -> URL? { resolvedMoviesURL }
    func tvURL() -> URL? { resolvedTVURL }
    func downloadURL() -> URL? { resolvedDownloadURL }

    // MARK: Internals

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func refreshResolvedURLs() {
        guard !isRefreshing else { return }
        isRefreshing = true

        defer { isRefreshing = false }

        let (mURL, mStale) = resolveBookmark(moviesBookmarkData)
        let (tURL, tStale) = resolveBookmark(tvBookmarkData)
        let (dURL, dStale) = resolveBookmark(downloadBookmarkData)

        resolvedMoviesURL = mURL
        resolvedTVURL = tURL
        resolvedDownloadURL = dURL

        // If stale, refresh bookmark data once (this avoids repeated “stale refresh” loops during UI renders)
        if mStale, let mURL, let refreshed = try? makeBookmark(for: mURL) { moviesBookmarkData = refreshed }
        if tStale, let tURL, let refreshed = try? makeBookmark(for: tURL) { tvBookmarkData = refreshed }
        if dStale, let dURL, let refreshed = try? makeBookmark(for: dURL) { downloadBookmarkData = refreshed }
    }

    private func resolveBookmark(_ data: Data?) -> (url: URL?, stale: Bool) {
        guard let data else { return (nil, false) }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return (nil, false) }
        return (url, stale)
    }
}
