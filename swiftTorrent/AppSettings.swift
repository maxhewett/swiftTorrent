//
//  AppSettings.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation
import SwiftUI
import Combine

enum MediaFileFilter {
    static let allowedExtensions: Set<String> = [
        "3gp", "3g2", "asf", "ass", "avi", "divx", "flac", "flv", "idx", "m2ts",
        "m4a", "m4b", "m4p", "m4r", "m4v", "mka", "mkv", "mov", "mp3", "mp4",
        "mpeg", "mpg", "nfo", "oga", "ogg", "ogm", "ogv", "opus", "smi", "srt", "ssa",
        "sub", "sup", "ts", "vob", "vtt", "wav", "webm", "wma", "wmv"
    ]

    static func shouldAllow(path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !ext.isEmpty else { return false }
        return allowedExtensions.contains(ext)
    }
}

struct FileExclusionRule: Codable, Hashable, Identifiable {
    let id: UUID
    var fileExtension: String
    var categoryIDs: Set<String>

    var appliesToAllCategories: Bool { categoryIDs.isEmpty }
}

struct RecentDownloadItem: Codable, Hashable, Identifiable {
    let id: UUID
    let torrentKey: String
    let torrentName: String
    let title: String
    let year: Int?
    let typeRaw: String
    let posterLocalPath: String?
    let posterRemoteURL: String?
    let startedAt: Date?
    let completedAt: Date
    let durationSeconds: Double?
    let outcome: String
    let cleanedDestinationPath: String?
    let source: String?

    var typeLabel: String {
        switch typeRaw.lowercased() {
        case "show":
            return "TV"
        default:
            return "Movie"
        }
    }
}

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
    private static let maxRecentDownloads = 100

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
        static let queueManagementMode = "swiftTorrent.settings.queueManagementMode"
        static let autoFilterNonMediaFiles = "swiftTorrent.settings.autoFilterNonMediaFiles"
        static let categoryDefinitions = "swiftTorrent.settings.categoryDefinitions"
        static let legacyCategories = "swiftTorrent.settings.categories"
        static let recentDownloads = "swiftTorrent.settings.recentDownloads"
        static let recentCompletionKeys = "swiftTorrent.settings.recentCompletionKeys"
        static let lastDownloadPath = "swiftTorrent.settings.lastDownloadPath"
        static let lastMoviesPath = "swiftTorrent.settings.lastMoviesPath"
        static let lastTVPath = "swiftTorrent.settings.lastTVPath"
        static let autoRemoveAfterSeedTime = "swiftTorrent.settings.autoRemoveAfterSeedTime"
        static let seedTimeLimitMinutes = "swiftTorrent.settings.seedTimeLimitMinutes"
        static let autoRemoveAfterSeedRatio = "swiftTorrent.settings.autoRemoveAfterSeedRatio"
        static let seedRatioLimit = "swiftTorrent.settings.seedRatioLimit"
        static let autoManageIdleDownloads = "swiftTorrent.settings.autoManageIdleDownloads"
        static let idleDownloadMinutes = "swiftTorrent.settings.idleDownloadMinutes"
        static let idleResumeMinutes = "swiftTorrent.settings.idleResumeMinutes"
        static let cleanedDestinationByTorrentKey = "swiftTorrent.settings.cleanedDestinationByTorrentKey"
        static let dockShowTransferOverlay = "swiftTorrent.settings.dockShowTransferOverlay"
        static let dockShowActiveCountBadge = "swiftTorrent.settings.dockShowActiveCountBadge"
        static let dockOverlayMetricMode = "swiftTorrent.settings.dockOverlayMetricMode"
        static let dockOverlayStyleMode = "swiftTorrent.settings.dockOverlayStyleMode"
        static let categoryHeaderSecondaryMode = "swiftTorrent.settings.categoryHeaderSecondaryMode"
        static let fileExclusionRules = "swiftTorrent.settings.fileExclusionRules"
        static let notificationsEnabled = "swiftTorrent.settings.notificationsEnabled"
        static let notifyCompletion = "swiftTorrent.settings.notifyCompletion"
        static let notifyNASDisconnected = "swiftTorrent.settings.notifyNASDisconnected"
        static let notifyStalledDownload = "swiftTorrent.settings.notifyStalledDownload"
        static let notifyCleanupFailure = "swiftTorrent.settings.notifyCleanupFailure"
        static let notifyAutoRemove = "swiftTorrent.settings.notifyAutoRemove"
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

    @Published var queueManagementMode: String = "automatic" {
        didSet { UserDefaults.standard.set(queueManagementMode, forKey: K.queueManagementMode) }
    }

    @Published var autoFilterNonMediaFiles: Bool = true {
        didSet { UserDefaults.standard.set(autoFilterNonMediaFiles, forKey: K.autoFilterNonMediaFiles) }
    }

    @Published var autoRemoveAfterSeedTime: Bool = false {
        didSet { UserDefaults.standard.set(autoRemoveAfterSeedTime, forKey: K.autoRemoveAfterSeedTime) }
    }

    @Published var seedTimeLimitMinutes: Int = 120 {
        didSet { UserDefaults.standard.set(seedTimeLimitMinutes, forKey: K.seedTimeLimitMinutes) }
    }

    @Published var autoRemoveAfterSeedRatio: Bool = false {
        didSet { UserDefaults.standard.set(autoRemoveAfterSeedRatio, forKey: K.autoRemoveAfterSeedRatio) }
    }

    @Published var seedRatioLimit: Double = 1.5 {
        didSet { UserDefaults.standard.set(seedRatioLimit, forKey: K.seedRatioLimit) }
    }

    @Published var autoManageIdleDownloads: Bool = true {
        didSet { UserDefaults.standard.set(autoManageIdleDownloads, forKey: K.autoManageIdleDownloads) }
    }

    @Published var idleDownloadMinutes: Int = 10 {
        didSet { UserDefaults.standard.set(idleDownloadMinutes, forKey: K.idleDownloadMinutes) }
    }

    @Published var idleResumeMinutes: Int = 3 {
        didSet { UserDefaults.standard.set(idleResumeMinutes, forKey: K.idleResumeMinutes) }
    }

    @Published var dockShowTransferOverlay: Bool = true {
        didSet { UserDefaults.standard.set(dockShowTransferOverlay, forKey: K.dockShowTransferOverlay) }
    }

    @Published var dockShowActiveCountBadge: Bool = true {
        didSet { UserDefaults.standard.set(dockShowActiveCountBadge, forKey: K.dockShowActiveCountBadge) }
    }

    @Published var dockOverlayMetricMode: String = "both" {
        didSet { UserDefaults.standard.set(dockOverlayMetricMode, forKey: K.dockOverlayMetricMode) }
    }

    @Published var dockOverlayStyleMode: String = "auto" {
        didSet { UserDefaults.standard.set(dockOverlayStyleMode, forKey: K.dockOverlayStyleMode) }
    }

    @Published var categoryHeaderSecondaryMode: String = "none" {
        didSet { UserDefaults.standard.set(categoryHeaderSecondaryMode, forKey: K.categoryHeaderSecondaryMode) }
    }

    @Published var notificationsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: K.notificationsEnabled) }
    }

    @Published var notifyCompletion: Bool = true {
        didSet { UserDefaults.standard.set(notifyCompletion, forKey: K.notifyCompletion) }
    }

    @Published var notifyNASDisconnected: Bool = true {
        didSet { UserDefaults.standard.set(notifyNASDisconnected, forKey: K.notifyNASDisconnected) }
    }

    @Published var notifyStalledDownload: Bool = true {
        didSet { UserDefaults.standard.set(notifyStalledDownload, forKey: K.notifyStalledDownload) }
    }

    @Published var notifyCleanupFailure: Bool = true {
        didSet { UserDefaults.standard.set(notifyCleanupFailure, forKey: K.notifyCleanupFailure) }
    }

    @Published var notifyAutoRemove: Bool = true {
        didSet { UserDefaults.standard.set(notifyAutoRemove, forKey: K.notifyAutoRemove) }
    }

    @Published private(set) var fileExclusionRules: [FileExclusionRule] {
        didSet {
            if let data = try? JSONEncoder().encode(fileExclusionRules) {
                UserDefaults.standard.set(data, forKey: K.fileExclusionRules)
            }
        }
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

    @Published private(set) var recentDownloads: [RecentDownloadItem] {
        didSet {
            if let data = try? JSONEncoder().encode(recentDownloads) {
                UserDefaults.standard.set(data, forKey: K.recentDownloads)
            }
        }
    }

    @Published private(set) var recentCompletionKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(recentCompletionKeys), forKey: K.recentCompletionKeys) }
    }

    @Published private(set) var resolvedMoviesURL: URL?
    @Published private(set) var resolvedTVURL: URL?
    @Published private(set) var resolvedDownloadURL: URL?
    @Published private(set) var lastMoviesPath: String = ""
    @Published private(set) var lastTVPath: String = ""
    @Published private(set) var lastDownloadPath: String = ""
    @Published private(set) var cleanedDestinationByTorrentKey: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(cleanedDestinationByTorrentKey) {
                UserDefaults.standard.set(data, forKey: K.cleanedDestinationByTorrentKey)
            }
        }
    }

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
        let loadedRecentDownloads: [RecentDownloadItem]
        if let data = UserDefaults.standard.data(forKey: K.recentDownloads),
           let decoded = try? JSONDecoder().decode([RecentDownloadItem].self, from: data) {
            let deduped = Self.deduplicatedRecentDownloads(decoded)
            loadedRecentDownloads = deduped
            if deduped.count != decoded.count,
               let encoded = try? JSONEncoder().encode(deduped) {
                UserDefaults.standard.set(encoded, forKey: K.recentDownloads)
            }
        } else {
            loadedRecentDownloads = []
        }
        self.recentDownloads = loadedRecentDownloads
        let storedCompletionKeys = UserDefaults.standard.stringArray(forKey: K.recentCompletionKeys) ?? []
        if storedCompletionKeys.isEmpty {
            self.recentCompletionKeys = Set(loadedRecentDownloads.compactMap { item in
                item.outcome.lowercased().contains("completed") ? item.torrentKey : nil
            })
        } else {
            self.recentCompletionKeys = Set(storedCompletionKeys)
        }

        self.resolvedMoviesURL = nil
        self.resolvedTVURL = nil
        self.resolvedDownloadURL = nil
        self.lastMoviesPath = UserDefaults.standard.string(forKey: K.lastMoviesPath) ?? ""
        self.lastTVPath = UserDefaults.standard.string(forKey: K.lastTVPath) ?? ""
        self.lastDownloadPath = UserDefaults.standard.string(forKey: K.lastDownloadPath) ?? ""
        if let data = UserDefaults.standard.data(forKey: K.cleanedDestinationByTorrentKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.cleanedDestinationByTorrentKey = decoded
        } else {
            self.cleanedDestinationByTorrentKey = [:]
        }

        let storedPort = UserDefaults.standard.integer(forKey: K.webUIPort)
        self.webUIPort = (1...65535).contains(storedPort) ? storedPort : 8080
        self.rpcUsername = UserDefaults.standard.string(forKey: K.rpcUsername) ?? ""
        self.rpcPassword = UserDefaults.standard.string(forKey: K.rpcPassword) ?? ""

        let storedMax = UserDefaults.standard.integer(forKey: K.maxActiveDownloads)
        self.maxActiveDownloads = storedMax > 0 ? storedMax : 5
        self.queueManagementMode = UserDefaults.standard.string(forKey: K.queueManagementMode) ?? "automatic"
        if UserDefaults.standard.object(forKey: K.autoFilterNonMediaFiles) == nil {
            self.autoFilterNonMediaFiles = true
        } else {
            self.autoFilterNonMediaFiles = UserDefaults.standard.bool(forKey: K.autoFilterNonMediaFiles)
        }
        if UserDefaults.standard.object(forKey: K.autoRemoveAfterSeedTime) == nil {
            self.autoRemoveAfterSeedTime = false
        } else {
            self.autoRemoveAfterSeedTime = UserDefaults.standard.bool(forKey: K.autoRemoveAfterSeedTime)
        }
        let storedSeedMinutes = UserDefaults.standard.integer(forKey: K.seedTimeLimitMinutes)
        self.seedTimeLimitMinutes = storedSeedMinutes > 0 ? storedSeedMinutes : 120
        if UserDefaults.standard.object(forKey: K.autoRemoveAfterSeedRatio) == nil {
            self.autoRemoveAfterSeedRatio = false
        } else {
            self.autoRemoveAfterSeedRatio = UserDefaults.standard.bool(forKey: K.autoRemoveAfterSeedRatio)
        }
        let storedRatio = UserDefaults.standard.double(forKey: K.seedRatioLimit)
        self.seedRatioLimit = storedRatio > 0 ? storedRatio : 1.5
        if UserDefaults.standard.object(forKey: K.autoManageIdleDownloads) == nil {
            self.autoManageIdleDownloads = true
        } else {
            self.autoManageIdleDownloads = UserDefaults.standard.bool(forKey: K.autoManageIdleDownloads)
        }
        let storedIdleMinutes = UserDefaults.standard.integer(forKey: K.idleDownloadMinutes)
        self.idleDownloadMinutes = storedIdleMinutes > 0 ? storedIdleMinutes : 10
        let storedIdleResumeMinutes = UserDefaults.standard.integer(forKey: K.idleResumeMinutes)
        self.idleResumeMinutes = storedIdleResumeMinutes > 0 ? storedIdleResumeMinutes : 3
        if UserDefaults.standard.object(forKey: K.dockShowTransferOverlay) == nil {
            self.dockShowTransferOverlay = true
        } else {
            self.dockShowTransferOverlay = UserDefaults.standard.bool(forKey: K.dockShowTransferOverlay)
        }
        if UserDefaults.standard.object(forKey: K.dockShowActiveCountBadge) == nil {
            self.dockShowActiveCountBadge = true
        } else {
            self.dockShowActiveCountBadge = UserDefaults.standard.bool(forKey: K.dockShowActiveCountBadge)
        }
        self.dockOverlayMetricMode = UserDefaults.standard.string(forKey: K.dockOverlayMetricMode) ?? "both"
        self.dockOverlayStyleMode = UserDefaults.standard.string(forKey: K.dockOverlayStyleMode) ?? "auto"
        self.categoryHeaderSecondaryMode = UserDefaults.standard.string(forKey: K.categoryHeaderSecondaryMode) ?? "none"
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: K.notificationsEnabled)
        self.notifyCompletion = Self.boolDefaultingToTrue(forKey: K.notifyCompletion)
        self.notifyNASDisconnected = Self.boolDefaultingToTrue(forKey: K.notifyNASDisconnected)
        self.notifyStalledDownload = Self.boolDefaultingToTrue(forKey: K.notifyStalledDownload)
        self.notifyCleanupFailure = Self.boolDefaultingToTrue(forKey: K.notifyCleanupFailure)
        self.notifyAutoRemove = Self.boolDefaultingToTrue(forKey: K.notifyAutoRemove)
        if let data = UserDefaults.standard.data(forKey: K.fileExclusionRules),
           let decoded = try? JSONDecoder().decode([FileExclusionRule].self, from: data) {
            self.fileExclusionRules = Self.normalizedFileExclusionRules(decoded)
        } else {
            self.fileExclusionRules = []
        }
        self.categoryDefinitions = Self.loadCategoryDefinitions()

        refreshResolvedURLs()
    }

    func shouldNotify(_ event: AppNotificationCenter.Event) -> Bool {
        switch event {
        case .completion: return notifyCompletion
        case .nasDisconnected: return notifyNASDisconnected
        case .stalledDownload: return notifyStalledDownload
        case .cleanupFailure: return notifyCleanupFailure
        case .autoRemove: return notifyAutoRemove
        }
    }

    private static func boolDefaultingToTrue(forKey key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

    func markCleaned(_ key: String) { cleanedTorrentKeys.insert(key) }
    func unmarkCleaned(_ key: String) { cleanedTorrentKeys.remove(key) }
    func hideTorrent(_ key: String) { hiddenTorrentKeys.insert(key) }
    func unhideTorrent(_ key: String) { hiddenTorrentKeys.remove(key) }
    func clearHiddenTorrents() { hiddenTorrentKeys = [] }

    func resetCleaned() {
        cleanedTorrentKeys = []
        hiddenTorrentKeys = []
    }

    func appendRecentDownload(_ item: RecentDownloadItem) {
        if item.outcome.lowercased().contains("completed"), recentCompletionKeys.contains(item.torrentKey) {
            return
        }
        if item.outcome.lowercased().contains("completed") {
            recentCompletionKeys.insert(item.torrentKey)
        }
        recentDownloads.insert(item, at: 0)
        if recentDownloads.count > Self.maxRecentDownloads {
            recentDownloads = Array(recentDownloads.prefix(Self.maxRecentDownloads))
        }
    }

    func clearRecentCompletionMark(for key: String) {
        recentCompletionKeys.remove(key)
    }

    func setCleanedDestination(_ path: String?, for key: String) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            cleanedDestinationByTorrentKey.removeValue(forKey: key)
        } else {
            cleanedDestinationByTorrentKey[key] = trimmed
        }
        if let index = recentDownloads.firstIndex(where: { $0.torrentKey == key }) {
            let item = recentDownloads[index]
            recentDownloads[index] = RecentDownloadItem(
                id: item.id,
                torrentKey: item.torrentKey,
                torrentName: item.torrentName,
                title: item.title,
                year: item.year,
                typeRaw: item.typeRaw,
                posterLocalPath: item.posterLocalPath,
                posterRemoteURL: item.posterRemoteURL,
                startedAt: item.startedAt,
                completedAt: item.completedAt,
                durationSeconds: item.durationSeconds,
                outcome: item.outcome,
                cleanedDestinationPath: trimmed.isEmpty ? nil : trimmed,
                source: item.source
            )
        }
    }

    func cleanedDestination(for key: String) -> String? {
        cleanedDestinationByTorrentKey[key]
    }

    func removeRecentDownload(id: UUID) {
        guard let index = recentDownloads.firstIndex(where: { $0.id == id }) else { return }
        let item = recentDownloads[index]
        recentDownloads.remove(at: index)
        clearRecentCompletionMark(for: item.torrentKey)
    }

    private static func deduplicatedRecentDownloads(_ items: [RecentDownloadItem]) -> [RecentDownloadItem] {
        var seenCompleted: Set<String> = []
        var deduped: [RecentDownloadItem] = []
        deduped.reserveCapacity(min(items.count, Self.maxRecentDownloads))

        for item in items {
            let isCompletedOutcome = item.outcome.lowercased().contains("completed")
            if isCompletedOutcome {
                if seenCompleted.contains(item.torrentKey) { continue }
                seenCompleted.insert(item.torrentKey)
            }
            deduped.append(item)
            if deduped.count == Self.maxRecentDownloads { break }
        }
        return deduped
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

    func addFileExclusionRule(fileExtension: String, categoryIDs: Set<String> = []) {
        guard let ext = Self.normalizeFileExtension(fileExtension) else { return }
        let normalizedCategories = Set(categoryIDs.compactMap { normalizedCategoryValue($0) })
        guard !fileExclusionRules.contains(where: { $0.fileExtension == ext && $0.categoryIDs == normalizedCategories }) else { return }
        fileExclusionRules.append(FileExclusionRule(id: UUID(), fileExtension: ext, categoryIDs: normalizedCategories))
    }

    func removeFileExclusionRule(id: UUID) {
        fileExclusionRules.removeAll { $0.id == id }
    }

    func setFileExclusionRuleCategories(id: UUID, categoryIDs: Set<String>) {
        guard let index = fileExclusionRules.firstIndex(where: { $0.id == id }) else { return }
        fileExclusionRules[index].categoryIDs = Set(categoryIDs.compactMap { normalizedCategoryValue($0) })
    }

    func shouldExcludeFile(path: String, category: String?) -> Bool {
        guard let ext = Self.normalizeFileExtension(URL(fileURLWithPath: path).pathExtension) else { return false }
        let normalizedCategory = normalizedCategoryValue(category)
        return fileExclusionRules.contains { rule in
            rule.fileExtension == ext && (rule.appliesToAllCategories || normalizedCategory.map(rule.categoryIDs.contains) == true)
        }
    }

    func shouldDownloadFile(path: String, category: String?) -> Bool {
        if shouldExcludeFile(path: path, category: category) { return false }
        return !autoFilterNonMediaFiles || MediaFileFilter.shouldAllow(path: path)
    }

    func setMoviesURL(_ url: URL) throws {
        moviesBookmarkData = try makeBookmark(for: url)
        rememberLastPath(url.path, key: K.lastMoviesPath)
    }

    func setTVURL(_ url: URL) throws {
        tvBookmarkData = try makeBookmark(for: url)
        rememberLastPath(url.path, key: K.lastTVPath)
    }

    func setDownloadURL(_ url: URL) throws {
        downloadBookmarkData = try makeBookmark(for: url)
        rememberLastPath(url.path, key: K.lastDownloadPath)
    }

    func moviesURL() -> URL? { resolvedMoviesURL }
    func tvURL() -> URL? { resolvedTVURL }
    func downloadURL() -> URL? { resolvedDownloadURL }

    var downloadPathForDisplay: String? {
        resolvedDownloadURL?.path ?? (lastDownloadPath.isEmpty ? nil : lastDownloadPath)
    }

    func preferredSavePath(for rawCategory: String?) -> String {
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() + "/Downloads")

        switch normalizedCategoryValue(rawCategory) {
        case "tv":
            if let url = resolvedTVURL { return url.path }
            if !lastTVPath.isEmpty { return lastTVPath }
        case "movie":
            if let url = resolvedMoviesURL { return url.path }
            if !lastMoviesPath.isEmpty { return lastMoviesPath }
        default:
            break
        }

        if let url = resolvedDownloadURL { return url.path }
        if !lastDownloadPath.isEmpty { return lastDownloadPath }
        return fallback
    }

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

        if let path = mURL?.path { rememberLastPath(path, key: K.lastMoviesPath) }
        if let path = tURL?.path { rememberLastPath(path, key: K.lastTVPath) }
        if let path = dURL?.path { rememberLastPath(path, key: K.lastDownloadPath) }
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

    private func rememberLastPath(_ path: String, key: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: key)
        switch key {
        case K.lastMoviesPath:
            lastMoviesPath = trimmed
        case K.lastTVPath:
            lastTVPath = trimmed
        case K.lastDownloadPath:
            lastDownloadPath = trimmed
        default:
            break
        }
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

    private static func normalizedFileExclusionRules(_ rules: [FileExclusionRule]) -> [FileExclusionRule] {
        rules.compactMap { rule in
            guard let ext = normalizeFileExtension(rule.fileExtension) else { return nil }
            return FileExclusionRule(id: rule.id, fileExtension: ext, categoryIDs: rule.categoryIDs)
        }
    }

    private static func normalizeFileExtension(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ext = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        guard !ext.isEmpty, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return ext
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
