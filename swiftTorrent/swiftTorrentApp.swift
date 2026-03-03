//
//  swiftTorrentApp.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import Combine

@main
struct swiftTorrentApp: App {
    @StateObject private var engine = TorrentEngine()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var appUpdater = AppUpdater()

    init() { }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear {
                    LocalWebServer.shared.attach(engine: engine)
                    LocalWebServer.shared.start(port: settings.webUIPort)
                }
                .onChange(of: settings.webUIPort) { _, newPort in
                    LocalWebServer.shared.start(port: newPort)
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
}
