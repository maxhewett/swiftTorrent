//
//  AppNotificationCenter.swift
//  swiftTorrent
//

import Foundation
import UserNotifications

final class AppNotificationCenter {
    static let shared = AppNotificationCenter()

    enum Event {
        case completion
        case nasDisconnected
        case stalledDownload
        case cleanupFailure
        case autoRemove
    }

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            RunDiagnostics.shared.log("Notification permission request failed: \(error.localizedDescription)", level: "ERROR")
            return false
        }
    }

    func send(_ event: Event, title: String, body: String, identifier: String? = nil) {
        let settings = AppSettings.shared
        guard settings.notificationsEnabled, settings.shouldNotify(event) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier ?? UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                Task { @MainActor in
                    RunDiagnostics.shared.log("Notification delivery failed: \(error.localizedDescription)", level: "ERROR")
                }
            }
        }
    }
}
