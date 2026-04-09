//
//  swiftTorrentApp.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import Combine
import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class RunDiagnostics {
    struct RunState: Codable {
        let launchedAt: Date
        var lastHeartbeatAt: Date
        var cleanShutdown: Bool
        var terminationReason: String?
        let appVersion: String
        let appBuild: String
    }

    static let shared = RunDiagnostics()

    private let isoFormatter = ISO8601DateFormatter()
    private var started = false
    private var timer: Timer?
    private var previousRunState: RunState?
    private var currentRunState: RunState?

    private init() {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func start() {
        guard !started else { return }
        started = true

        previousRunState = loadState()
        currentRunState = RunState(
            launchedAt: Date(),
            lastHeartbeatAt: Date(),
            cleanShutdown: false,
            terminationReason: nil,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
        persistCurrentState()

        log("App launched (v\(currentRunState?.appVersion ?? "unknown"), build \(currentRunState?.appBuild ?? "unknown"))")

        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordHeartbeat()
            }
        }

#if canImport(AppKit)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.markCleanShutdown(reason: "normal_termination")
            }
        }
#endif
    }

    func markCleanShutdown(reason: String) {
        guard currentRunState != nil else { return }
        currentRunState?.cleanShutdown = true
        currentRunState?.terminationReason = reason
        currentRunState?.lastHeartbeatAt = Date()
        persistCurrentState()
        log("App terminating (\(reason)).")
    }

    func log(_ message: String, level: String = "INFO") {
        let ts = isoFormatter.string(from: Date())
        let line = "\(ts) [\(level)] \(message)\n"
        print("[\(level)] \(message)")

        let url = logURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try Data(line.utf8).write(to: url, options: [.atomic])
            }
        } catch {
            print("[WARN] Failed to write diagnostics log: \(error.localizedDescription)")
        }
    }

    func diagnosticsSnapshot(logLines: Int) -> [String: Any] {
        let previous = previousRunState
        let current = currentRunState
        let suspectedCrash = previous.map { !$0.cleanShutdown } ?? false

        return [
            "generatedAt": isoFormatter.string(from: Date()),
            "suspectedPreviousCrash": suspectedCrash,
            "previousRun": runStatePayload(previous) ?? NSNull(),
            "currentRun": runStatePayload(current) ?? NSNull(),
            "recentLogs": recentLogLines(limit: max(1, min(logLines, 1000)))
        ]
    }

    private func recordHeartbeat() {
        guard currentRunState != nil else { return }
        currentRunState?.lastHeartbeatAt = Date()
        persistCurrentState()
    }

    private func runStatePayload(_ state: RunState?) -> [String: Any]? {
        guard let state else { return nil }
        return [
            "launchedAt": isoFormatter.string(from: state.launchedAt),
            "lastHeartbeatAt": isoFormatter.string(from: state.lastHeartbeatAt),
            "cleanShutdown": state.cleanShutdown,
            "terminationReason": state.terminationReason ?? NSNull(),
            "appVersion": state.appVersion,
            "appBuild": state.appBuild
        ]
    }

    private func recentLogLines(limit: Int) -> [String] {
        let url = logURL()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > limit else { return lines }
        return Array(lines.suffix(limit))
    }

    private func persistCurrentState() {
        guard let state = currentRunState else { return }
        let url = stateURL()
        do {
            let data = try JSONEncoder().encode(state)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[WARN] Failed to persist runtime state: \(error.localizedDescription)")
        }
    }

    private func loadState() -> RunState? {
        let url = stateURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RunState.self, from: data)
    }

    private func baseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("swiftTorrent", isDirectory: true)
    }

    private func stateURL() -> URL {
        baseDirectory().appendingPathComponent("runtime-state.json")
    }

    private func logURL() -> URL {
        baseDirectory().appendingPathComponent("runtime.log")
    }
}

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
                    RunDiagnostics.shared.start()
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
