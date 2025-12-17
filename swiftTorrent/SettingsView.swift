//
//  SettingsView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var errorText: String? = nil
    

    // ✅ ADD THIS
    @State private var webUIPortText: String = ""

    var body: some View {
        Form {
            Section("Automation") {
                Toggle("Auto-cleanup when download completes", isOn: $settings.autoCleanupEnabled)

                Button("Reset cleanup history (allow re-cleaning completed torrents)") {
                    settings.resetCleaned()
                }
            }

            Section("Web UI") {
                LabeledContent("Port") {
                    TextField("8080", text: $webUIPortText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: webUIPortText) {
                            let digitsOnly = webUIPortText.filter { $0.isNumber }
                            if digitsOnly != webUIPortText { webUIPortText = digitsOnly }

                            guard let v = Int(digitsOnly), (1...65535).contains(v) else { return }
                            settings.webUIPort = v
                        }
                }

                Text("WebUI: http://127.0.0.1:\(settings.webUIPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                if webUIPortText.isEmpty {
                    webUIPortText = String(settings.webUIPort)
                }
            }
            .onChange(of: settings.webUIPort) {
                let s = String(settings.webUIPort)
                if webUIPortText != s { webUIPortText = s }
            }
            
            Section("RPC (Sonarr/Radarr)") {
                TextField("Username (optional)", text: $settings.rpcUsername)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password (optional)", text: $settings.rpcPassword)
                    .textFieldStyle(.roundedBorder)

                Text("Leave blank to disable authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Download Client") {
                destinationRow(
                    title: "Initial download folder",
                    url: settings.resolvedDownloadURL
                ) {
                    FolderPicker.pickFolder { url in
                        guard let url else { return }
                        Task { @MainActor in
                            do {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                try settings.setDownloadURL(url)
                                errorText = nil
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    }
                }
            }

            Section("Destinations") {
                destinationRow(
                    title: "Movies folder",
                    url: settings.resolvedMoviesURL
                ) {
                    FolderPicker.pickFolder { url in
                        guard let url else { return }
                        Task { @MainActor in
                            do {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                try settings.setMoviesURL(url)
                                errorText = nil
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    }
                }

                destinationRow(
                    title: "TV folder",
                    url: settings.resolvedTVURL
                ) {
                    FolderPicker.pickFolder { url in
                        guard let url else { return }
                        Task { @MainActor in
                            do {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }
                                try settings.setTVURL(url)
                                errorText = nil
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func destinationRow(title: String, url: URL?, pickAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(url?.path ?? "Not set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Choose…", action: pickAction)
        }
    }
}
