//
//  SettingsView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            DownloadsSettingsTab()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            IntegrationSettingsTab()
                .tabItem { Label("Integration", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var confirmResetCleanup = false

    var body: some View {
        Form {
            Section {
                Toggle("Auto-cleanup when download completes", isOn: $settings.autoCleanupEnabled)
                    .help("Automatically move completed downloads to their destination folders.")
            } header: {
                Text("Behaviour")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reset cleanup history")
                        Text("Allows previously cleaned torrents to be moved again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset…") { confirmResetCleanup = true }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Maintenance")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.bottom, 12)
        .confirmationDialog("Reset cleanup history?", isPresented: $confirmResetCleanup, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { settings.resetCleaned() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Completed torrents that were already moved will be eligible for cleanup again.")
        }
    }
}

// MARK: - Downloads

private struct DownloadsSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                folderRow(label: "Download folder",
                          systemImage: "arrow.down.circle",
                          url: settings.resolvedDownloadURL) {
                    pickFolder { url in try settings.setDownloadURL(url) }
                }
            } header: {
                Text("Default Location")
            } footer: {
                Text("Where new torrents are saved while downloading.")
            }

            Section {
                LabeledContent("Max active downloads") {
                    HStack(spacing: 8) {
                        Stepper(
                            value: $settings.maxActiveDownloads,
                            in: 1...20,
                            step: 1
                        ) { EmptyView() }
                        Text(settings.maxActiveDownloads == 0
                             ? "Unlimited"
                             : "\(settings.maxActiveDownloads)")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .leading)
                    }
                }
            } header: {
                Text("Queue")
            } footer: {
                Text("Torrents beyond this limit are queued and start automatically when a slot opens.")
            }

            Section {
                folderRow(label: "Movies",
                          systemImage: "film",
                          url: settings.resolvedMoviesURL) {
                    pickFolder { url in try settings.setMoviesURL(url) }
                }

                folderRow(label: "TV Shows",
                          systemImage: "tv",
                          url: settings.resolvedTVURL) {
                    pickFolder { url in try settings.setTVURL(url) }
                }
            } header: {
                Text("Destinations")
            } footer: {
                Text("Completed downloads are moved here when auto-cleanup is enabled.")
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.bottom, 12)
    }

    private func folderRow(label: String, systemImage: String, url: URL?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(shortenPath(url?.path))
                    .font(.caption)
                    .foregroundStyle(url == nil ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Choose…", action: action)
        }
        .padding(.vertical, 2)
    }

    private func pickFolder(setter: @escaping (URL) throws -> Void) {
        FolderPicker.pickFolder { url in
            guard let url else { return }
            Task { @MainActor in
                do {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try setter(url)
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func shortenPath(_ path: String?) -> String {
        guard let path else { return "Not set" }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Integration

private struct IntegrationSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var webUIPortText: String = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Port") {
                    TextField("8080", text: $webUIPortText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: webUIPortText) {
                            let digits = webUIPortText.filter { $0.isNumber }
                            if digits != webUIPortText { webUIPortText = digits }
                            guard let v = Int(digits), (1...65535).contains(v) else { return }
                            settings.webUIPort = v
                        }
                }

                LabeledContent("Address") {
                    Text("http://127.0.0.1:\(settings.webUIPort)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Web Interface")
            } footer: {
                Text("Access swiftTorrent from a browser on this machine.")
            }

            Section {
                LabeledContent("Username") {
                    TextField("Optional", text: $settings.rpcUsername)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180)
                }

                LabeledContent("Password") {
                    SecureField("Optional", text: $settings.rpcPassword)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180)
                }
            } header: {
                Text("Sonarr & Radarr (RPC)")
            } footer: {
                Text("Credentials required by Sonarr/Radarr when connecting to this client. Leave blank to allow unauthenticated access.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.bottom, 12)
        .onAppear {
            if webUIPortText.isEmpty { webUIPortText = String(settings.webUIPort) }
        }
        .onChange(of: settings.webUIPort) {
            let s = String(settings.webUIPort)
            if webUIPortText != s { webUIPortText = s }
        }
    }
}
