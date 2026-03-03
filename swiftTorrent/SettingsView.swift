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
        .frame(width: 720, height: 640)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var appUpdater: AppUpdater
    @State private var confirmResetCleanup = false

    var body: some View {
        SettingsScrollLayout {
            SettingsCard(
                title: "Behaviour",
                subtitle: "Choose what swiftTorrent does automatically while downloads finish and move around the app."
            ) {
                Toggle("Auto-cleanup when download completes", isOn: $settings.autoCleanupEnabled)
                    .help("Automatically move completed downloads to their destination folders.")
            }

            SettingsCard(
                title: "Maintenance",
                subtitle: "Cleanup history prevents the same finished torrent from being moved twice. Reset it if you want to re-run cleanup on older items."
            ) {
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
            }

            SettingsCard(
                title: "Updates",
                subtitle: "Sparkle checks the GitHub-hosted appcast for new releases. The feed URL and public key must already be configured in the app target."
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Software updates")
                        Text(appUpdater.isConfigured
                             ? "Checks GitHub-hosted Sparkle updates."
                             : "Set SUFeedURL and SUPublicEDKey to enable Sparkle updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now") { appUpdater.checkForUpdates() }
                        .buttonStyle(.bordered)
                        .disabled(!appUpdater.canCheckForUpdates)
                }
            }
        }
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
    @State private var newCategoryID = ""
    @State private var newCategoryTitle = ""
    @State private var newCategorySymbol = "tag"

    var body: some View {
        SettingsScrollLayout {
            SettingsCard(
                title: "Default Location",
                subtitle: "Where new torrents are saved while they are downloading."
            ) {
                folderRow(label: "Download folder",
                          systemImage: "arrow.down.circle",
                          url: settings.resolvedDownloadURL) {
                    pickFolder { url in try settings.setDownloadURL(url) }
                }
            }

            SettingsCard(
                title: "Queue",
                subtitle: "Torrents beyond this limit stay queued until an active slot becomes available."
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Max active downloads")
                        Text("Set a practical cap if you want slower drives or connections to stay predictable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Stepper(value: $settings.maxActiveDownloads, in: 1...20, step: 1) {
                            EmptyView()
                        }
                        Text("\(settings.maxActiveDownloads)")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            SettingsCard(
                title: "Destinations",
                subtitle: "Completed downloads are moved here when auto-cleanup is enabled. These destinations back the built-in Movies and TV categories."
            ) {
                VStack(spacing: 12) {
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
                }
            }

            SettingsCard(
                title: "Categories",
                subtitle: "Category key is the stored value used by swiftTorrent and integrations. Display title is what the UI shows. Symbol uses the SF Symbols name that appears beside the title."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsHint(title: "Built-in categories", detail: "movie and tv are fixed because they map directly to the app's Movies and TV organisation and downstream cleanup behaviour.")
                        SettingsHint(title: "SF Symbols", detail: "Use names like film, tv, shippingbox, or tag. The symbol preview updates from the name you enter.")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add category")
                            .font(.headline)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Category key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("archive", text: $newCategoryID)
                                    .textFieldStyle(.roundedBorder)
                                Text("Lowercase internal value. Keep it stable once used.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Display title")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Archive", text: $newCategoryTitle)
                                    .textFieldStyle(.roundedBorder)
                                Text("Shown in pickers and section labels.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Symbol")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("shippingbox", text: $newCategorySymbol)
                                    .textFieldStyle(.roundedBorder)
                                Text("SF Symbols name.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Preview")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                CategoryPreviewPill(
                                    title: newCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Preview" : newCategoryTitle,
                                    symbol: newCategorySymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tag" : newCategorySymbol
                                )
                                Spacer(minLength: 0)
                                Button("Add") {
                                    settings.addCategory(id: newCategoryID, title: newCategoryTitle, symbol: newCategorySymbol)
                                    newCategoryID = ""
                                    newCategoryTitle = ""
                                    newCategorySymbol = "tag"
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newCategoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Configured categories")
                            .font(.headline)

                        ForEach(settings.categoryDefinitionsForUI) { category in
                            CategoryEditorCard(category: category)
                        }
                    }
                }
            }

            if let errorText {
                SettingsCard(title: "Folder Access", subtitle: "Folder selection failed.") {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
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
                .buttonStyle(.bordered)
        }
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

private struct CategoryEditorCard: View {
    @ObservedObject private var settings = AppSettings.shared
    let category: CategoryDefinition
    @State private var title: String = ""
    @State private var symbol: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CategoryPreviewPill(title: title, symbol: symbol)
                        if category.isLocked {
                            Label("Built-in", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Stored as \(category.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !category.isLocked {
                    HStack(spacing: 8) {
                        Button("Save") {
                            settings.updateCategory(id: category.id, title: title, symbol: symbol)
                        }
                        .buttonStyle(.bordered)

                        Button("Remove", role: .destructive) {
                            settings.removeCategory(category.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Display title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .disabled(category.isLocked)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Symbol")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Symbol", text: $symbol)
                        .textFieldStyle(.roundedBorder)
                        .disabled(category.isLocked)
                }
                .frame(width: 150)
            }

            Text(category.isLocked
                 ? "This category is locked because it maps directly to swiftTorrent's built-in Movies or TV handling."
                 : "This title and symbol appear in the torrent inspector, add torrent sheet, and category section headers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .onAppear {
            title = category.title
            symbol = category.symbol
        }
        .onChange(of: category.title) { _, newValue in
            title = newValue
        }
        .onChange(of: category.symbol) { _, newValue in
            symbol = newValue
        }
    }
}

private struct CategoryPreviewPill: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title.isEmpty ? "Untitled" : title, systemImage: symbol.isEmpty ? "tag" : symbol)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08), in: Capsule())
    }
}

// MARK: - Integration

private struct IntegrationSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var webUIPortText: String = ""

    var body: some View {
        SettingsScrollLayout {
            SettingsCard(
                title: "Web Interface",
                subtitle: "Access swiftTorrent from a browser on this machine. The address below is the exact local URL to open."
            ) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Port")
                            Text("Use a free local port between 1 and 65535.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

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

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Address")
                            Text("This is the local address browsers or tools on this machine should use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(verbatim: "http://127.0.0.1:\(settings.webUIPort)")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            SettingsCard(
                title: "Sonarr & Radarr (RPC)",
                subtitle: "These credentials are what Sonarr and Radarr use when connecting to swiftTorrent's RPC interface. Leave both blank if you want no authentication."
            ) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Username")
                            Text("Optional. Needed only if you want RPC auth enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        TextField("Optional", text: $settings.rpcUsername)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 220)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Password")
                            Text("Optional. Stored locally for RPC access.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        SecureField("Optional", text: $settings.rpcPassword)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 220)
                    }
                }
            }
        }
        .onAppear {
            if webUIPortText.isEmpty { webUIPortText = String(settings.webUIPort) }
        }
        .onChange(of: settings.webUIPort) {
            let s = String(settings.webUIPort)
            if webUIPortText != s { webUIPortText = s }
        }
    }
}

private struct SettingsScrollLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

private struct SettingsHint: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
