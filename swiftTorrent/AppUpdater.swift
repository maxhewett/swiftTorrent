import Foundation
import Combine

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    enum UpdateChannel: String, CaseIterable, Identifiable {
        case stable
        case beta

        var id: String { rawValue }

        var label: String {
            switch self {
            case .stable:
                return "Stable"
            case .beta:
                return "Beta"
            }
        }

        var symbolName: String {
            switch self {
            case .stable:
                return "checkmark.seal"
            case .beta:
                return "flask.fill"
            }
        }
    }

    private static let fallbackFeedURL = "https://maxhewett.github.io/swiftTorrent/appcast.xml"
    private static let updateChannelDefaultsKey = "swiftTorrentAppUpdateChannel"

    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var feedURLString = ""
    @Published private(set) var hasPublicKey = false
    @Published private(set) var selectedChannel: UpdateChannel = .stable

#if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif
    private let stableFeedURL: String

    init(bundle: Bundle = .main) {
        let persistedChannelRaw = UserDefaults.standard.string(forKey: Self.updateChannelDefaultsKey) ?? UpdateChannel.stable.rawValue
        let persistedChannel = UpdateChannel(rawValue: persistedChannelRaw) ?? .stable
        selectedChannel = persistedChannel

        let bundleFeedURL = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundlePublicKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let feedURL = bundleFeedURL.isEmpty ? Self.fallbackFeedURL : bundleFeedURL
        stableFeedURL = feedURL
        let configured = !feedURL.isEmpty && !bundlePublicKey.isEmpty

        let initialFeedURL = Self.resolvedFeedURL(stableFeedURL: feedURL, channel: persistedChannel)

        super.init()

        feedURLString = initialFeedURL
        hasPublicKey = !bundlePublicKey.isEmpty
        isConfigured = configured

#if canImport(Sparkle)
        if configured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            canCheckForUpdates = true
        } else {
            updaterController = nil
            canCheckForUpdates = false
        }
#else
        canCheckForUpdates = false
#endif
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
#endif
    }

    func setUpdateChannel(_ channel: UpdateChannel) {
        guard selectedChannel != channel else { return }
        selectedChannel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: Self.updateChannelDefaultsKey)
        feedURLString = resolvedFeedURL(for: channel)
    }

    private func resolvedFeedURL(for channel: UpdateChannel) -> String {
        Self.resolvedFeedURL(stableFeedURL: stableFeedURL, channel: channel)
    }

    private static func resolvedFeedURL(stableFeedURL: String, channel: UpdateChannel) -> String {
        switch channel {
        case .stable:
            return stableFeedURL
        case .beta:
            return betaFeedURL(from: stableFeedURL)
        }
    }

    private static func betaFeedURL(from stableFeedURL: String) -> String {
        guard var components = URLComponents(string: stableFeedURL) else {
            return stableFeedURL
        }
        let path = components.path
        let betaPath: String
        if path.hasSuffix("/appcast.xml") {
            betaPath = String(path.dropLast("/appcast.xml".count)) + "/beta/appcast.xml"
        } else if path.hasSuffix("appcast.xml") {
            betaPath = String(path.dropLast("appcast.xml".count)) + "beta/appcast.xml"
        } else {
            betaPath = path.hasSuffix("/") ? path + "beta/appcast.xml" : path + "/beta/appcast.xml"
        }
        components.path = betaPath
        return components.url?.absoluteString ?? stableFeedURL
    }
}

#if canImport(Sparkle)
extension AppUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.resolvedFeedURL(stableFeedURL: stableFeedURL, channel: selectedChannel)
    }
}
#endif
