import Foundation
import SwiftUI
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var feedURLString = ""
    @Published private(set) var hasPublicKey = false

#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
#endif

    init(bundle: Bundle = .main) {
        let feedURL = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configured = !feedURL.isEmpty && !publicKey.isEmpty

        feedURLString = feedURL
        hasPublicKey = !publicKey.isEmpty
        isConfigured = configured

#if canImport(Sparkle)
        if configured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
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
}
