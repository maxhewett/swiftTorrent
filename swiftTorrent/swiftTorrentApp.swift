//
//  swiftTorrentApp.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class MagnetImportCoordinator: ObservableObject {
    @Published var pendingMagnet: String?

    func present(magnet: String) {
        pendingMagnet = magnet
    }

    func clear() {
        pendingMagnet = nil
    }
}

@main
struct swiftTorrentApp: App {
    @StateObject private var engine = TorrentEngine()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var magnetImport = MagnetImportCoordinator()

    init() { }

    var body: some Scene {
        Window("swiftTorrent", id: "main") {
            ContentView()
                .environmentObject(engine)
                .environmentObject(magnetImport)
                .onAppear {
                    LocalWebServer.shared.attach(engine: engine)
                    LocalWebServer.shared.start(port: settings.webUIPort)
                }
                .onChange(of: settings.webUIPort) { _, newPort in
                    LocalWebServer.shared.start(port: newPort)
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .environmentObject(appUpdater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appUpdater)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "magnet" else { return }
#if canImport(AppKit)
        NSApp.activate(ignoringOtherApps: true)
#endif
        magnetImport.present(magnet: url.absoluteString)
    }
}
