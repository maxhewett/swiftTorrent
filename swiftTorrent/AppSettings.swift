//
//  AppSettings.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation
import SwiftUI
import Combine

struct CategoryDefinition: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var symbol: String
    let isLocked: Bool

    init(id: String, title: String, symbol: String, isLocked: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.isLocked = isLocked
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum K {
        static let autoCleanupEnabled = "swiftTorrent.settings.autoCleanupEnabled"
        static let moviesBookmark = "swiftTorrent.settings.moviesBookmark"
        static let tvBookmark = "swiftTorrent.settings.tvBookmark"
        static let cleanedKeys = "swiftTorrent.settings.cleanedTorrentKeys"
        static let hiddenKeys = "swiftTorrent.settings.hiddenTorrentKeys"
        static let downloadBookmark = "swiftTorrent.settings.downloadBookmark"
        static let webUIPort = "swiftTorrent.settings.webUIPort"
        static let rpcUsername = "swiftTorrent.settings.rpcUsername"
        static let rpcPassword = "swiftTorrent.settings.rpcPassword"
        static let maxActiveDownloads = "swiftTorrent.settings.maxActiveDownloads"
        static let categoryDefinitions = "swiftTorrent.settings.categoryDefinitions"
        static let legacyCategories = "swiftTorrent.settings.categories"
    }

    static let defaultCategories: [CategoryDefinition] = [
        CategoryDefinition(id: "movie", title: "Movies", symbol: "film", isLocked: true),
        CategoryDefinition(id: "tv", title: "TV", symbol: "tv", isLocked: true)
    ]

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

    @Published var maxActiveDownloads: Int = 5 {
        didSet { UserDefaults.standard.set(maxActiveDownloads, forKey: K.maxActiveDownloads) }
    }

    @Published var categoryDefinitions: [CategoryDefinition] = [] {
        didSet {
            let normalized = Self.normalizeCategoryDefinitions(categoryDefinitions)
            if normalized != categoryDefinitions {
                categoryDefinitions = normalized
                return
            }
            if let data = try? JSONEncoder().encode(categoryDefinitions) {
                UserDefaults.standard.set(data, forKey: K.categoryDefinitions)
            }
        }
    }

    @Published var downloadBookmarkData: Data? {
        didSet {
            UserDefaults.standard.set(downloadBookmarkData, forKey: K.downloadBookmark)
            refreshResolvedURLs()
        }
    }

    @Published private(set) var cleanedTorrentKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(cleanedTorrentKeys), forKey: K.cleanedKeys) }
    }

    @Published private(set) var hiddenTorrentKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenTorrentKeys), forKey: K.hiddenKeys) }
    }

    @Published private(set) var resolvedMoviesURL: URL?
    @Published private(set) var resolvedTVURL: URL?
    @Published private(set) var resolvedDownloadURL: URL?

    private var isRefreshing = false

    var categoryDefinitionsForUI: [CategoryDefinition] {
        categoryDefinitions
    }

    private init() {
        self.autoCleanupEnabled = UserDefaults.standard.bool(forKey: K.autoCleanupEnabled)
        self.moviesBookmarkData = UserDefaults.standard.data(forKey: K.moviesBookmark)
        self.tvBookmarkData = UserDefaults.standard.data(forKey: K.tvBookmark)
        self.downloadBookmarkData = UserDefaults.standard.data(forKey: K.downloadBookmark)

        let arr = UserDefaults.standard.stringArray(forKey: K.cleanedKeys) ?? []
        self.cleanedTorrentKeys = Set(arr)
        let hiddenArr = UserDefaults.standard.stringArray(forKey: K.hiddenKeys) ?? []
        self.hiddenTorrentKeys = Set(hiddenArr)

        self.resolvedMoviesURL = nil
        self.resolvedTVURL = nil
        self.resolvedDownloadURL = nil

        let storedPort = UserDefaults.standard.integer(forKey: K.webUIPort)
        self.webUIPort = (1...65535).contains(storedPort) ? storedPort : 8080
        self.rpcUsername = UserDefaults.standard.string(forKey: K.rpcUsername) ?? ""
        self.rpcPassword = UserDefaults.standard.string(forKey: K.rpcPassword) ?? ""

        let storedMax = UserDefaults.standard.integer(forKey: K.maxActiveDownloads)
        self.maxActiveDownloads = storedMax > 0 ? storedMax : 5
        self.categoryDefinitions = Self.loadCategoryDefinitions()

        refreshResolvedURLs()
    }

    func markCleaned(_ key: String) { cleanedTorrentKeys.insert(key) }
    func unmarkCleaned(_ key: String) { cleanedTorrentKeys.remove(key) }
    func hideTorrent(_ key: String) { hiddenTorrentKeys.insert(key) }
    func unhideTorrent(_ key: String) { hiddenTorrentKeys.remove(key) }

    func resetCleaned() {
        cleanedTorrentKeys = []
        hiddenTorrentKeys = []
    }

    func addCategory(id: String, title: String, symbol: String) {
        guard let normalizedID = Self.normalizeCategoryID(id) else { return }
        guard !categoryDefinitions.contains(where: { $0.id == normalizedID }) else { return }

        categoryDefinitions.append(
            CategoryDefinition(
                id: normalizedID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedID.capitalized : title.trimmingCharacters(in: .whitespacesAndNewlines),
                symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tag" : symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    func updateCategory(id: String, title: String, symbol: String) {
        guard let index = categoryDefinitions.firstIndex(where: { $0.id == id }) else { return }
        guard !categoryDefinitions[index].isLocked else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        categoryDefinitions[index].title = trimmedTitle.isEmpty ? id.capitalized : trimmedTitle
        categoryDefinitions[index].symbol = trimmedSymbol.isEmpty ? "tag" : trimmedSymbol
    }

    func removeCategory(_ id: String) {
        guard let index = categoryDefinitions.firstIndex(where: { $0.id == id }) else { return }
        guard !categoryDefinitions[index].isLocked else { return }
        categoryDefinitions.remove(at: index)
    }

    func categoryDefinition(for rawCategory: String?) -> CategoryDefinition? {
        guard let normalized = normalizedCategoryValue(rawCategory) else { return nil }
        return categoryDefinitions.first(where: { $0.id == normalized })
    }

    func normalizedCategoryValue(_ rawCategory: String?) -> String? {
        guard let normalized = Self.normalizeCategoryID(rawCategory) else { return nil }
        switch normalized {
        case "movies", "movies-radarr", "radarr":
            return "movie"
        case "tv-sonarr", "sonarr", "shows":
            return "tv"
        default:
            return normalized
        }
    }

    func setMoviesURL(_ url: URL) throws {
        moviesBookmarkData = try makeBookmark(for: url)
    }

    func setTVURL(_ url: URL) throws {
        tvBookmarkData = try makeBookmark(for: url)
    }

    func setDownloadURL(_ url: URL) throws {
        downloadBookmarkData = try makeBookmark(for: url)
    }

    func moviesURL() -> URL? { resolvedMoviesURL }
    func tvURL() -> URL? { resolvedTVURL }
    func downloadURL() -> URL? { resolvedDownloadURL }

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

    private static func loadCategoryDefinitions() -> [CategoryDefinition] {
        if let data = UserDefaults.standard.data(forKey: K.categoryDefinitions),
           let decoded = try? JSONDecoder().decode([CategoryDefinition].self, from: data) {
            return normalizeCategoryDefinitions(decoded)
        }

        let legacy = UserDefaults.standard.stringArray(forKey: K.legacyCategories) ?? []
        let migrated = legacy.compactMap { value -> CategoryDefinition? in
            guard let normalized = normalizeCategoryID(value) else { return nil }
            switch normalized {
            case "movie", "movies", "movies-radarr", "radarr":
                return nil
            case "tv", "tv-sonarr", "sonarr":
                return nil
            default:
                return CategoryDefinition(id: normalized, title: normalized.capitalized, symbol: "tag")
            }
        }
        return normalizeCategoryDefinitions(defaultCategories + migrated)
    }

    private static func normalizeCategoryDefinitions(_ values: [CategoryDefinition]) -> [CategoryDefinition] {
        var byID: [String: CategoryDefinition] = [:]

        for item in defaultCategories {
            byID[item.id] = item
        }

        for item in values {
            guard let normalizedID = normalizeCategoryID(item.id) else { continue }
            if let existing = byID[normalizedID], existing.isLocked {
                continue
            }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = item.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            byID[normalizedID] = CategoryDefinition(
                id: normalizedID,
                title: title.isEmpty ? normalizedID.capitalized : title,
                symbol: symbol.isEmpty ? "tag" : symbol,
                isLocked: item.isLocked
            )
        }

        let defaults = defaultCategories.compactMap { byID.removeValue(forKey: $0.id) ?? $0 }
        let customs = byID.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return defaults + customs
    }

    private static func normalizeCategoryID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let allowed = trimmed.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? nil : collapsed
    }
}
