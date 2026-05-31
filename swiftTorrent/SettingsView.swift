//
//  SettingsView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreServices

struct SettingsView: View {
    var onClose: (() -> Void)?

    private enum Section: String, CaseIterable, Identifiable {
        case general
        case downloads
        case appearance
        case integration

        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .downloads: return "Downloads"
            case .appearance: return "Appearance"
            case .integration: return "Integration"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gear"
            case .downloads: return "arrow.down.circle"
            case .appearance: return "dock.rectangle"
            case .integration: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @State private var selection: Section? = .general
    @State private var activeSubsectionID: String?
    @State private var scrollRequestID: String?

    private struct Subsection: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
    }

    private var currentSelection: Section { selection ?? .general }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            settingsDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selection) { _, newSelection in
            let section = newSelection ?? .general
            activeSubsectionID = subsections(for: section).first?.id
            scrollRequestID = activeSubsectionID
        }
        .onAppear {
            let section = selection ?? .general
            activeSubsectionID = subsections(for: section).first?.id
        }
    }

    private func sectionDescription(_ section: Section) -> String {
        switch section {
        case .general:
            return "Manage general app behavior, maintenance, and updates."
        case .downloads:
            return "Control download paths, queue behavior, seeding, and categories."
        case .appearance:
            return "Customize Dock icon telemetry and visual display options."
        case .integration:
            return "Configure Web UI, RPC credentials, and magnet link handling."
        }
    }

    private func subsections(for section: Section) -> [Subsection] {
        switch section {
        case .general:
            return [
                Subsection(id: "general.behaviour", title: "Behaviour", symbol: "slider.horizontal.3"),
                Subsection(id: "general.maintenance", title: "Maintenance", symbol: "wrench.and.screwdriver"),
                Subsection(id: "general.updates", title: "Updates", symbol: "arrow.triangle.2.circlepath")
            ]
        case .downloads:
            return [
                Subsection(id: "downloads.default", title: "Default Location", symbol: "folder"),
                Subsection(id: "downloads.queue", title: "Queue", symbol: "line.3.horizontal.decrease.circle"),
                Subsection(id: "downloads.seeding", title: "Seeding", symbol: "dot.radiowaves.left.and.right"),
                Subsection(id: "downloads.destinations", title: "Destinations", symbol: "externaldrive"),
                Subsection(id: "downloads.categories", title: "Categories", symbol: "tag")
            ]
        case .appearance:
            return [
                Subsection(id: "appearance.dock", title: "Dock Icon", symbol: "dock.rectangle"),
                Subsection(id: "appearance.sidebar", title: "Sidebar Labels", symbol: "list.bullet.rectangle")
            ]
        case .integration:
            return [
                Subsection(id: "integration.web", title: "Web Interface", symbol: "network"),
                Subsection(id: "integration.rpc", title: "Sonarr/Radarr RPC", symbol: "lock.shield"),
                Subsection(id: "integration.magnet", title: "Magnet Links", symbol: "link")
            ]
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            ForEach(Section.allCases) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = section
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.callout.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(currentSelection == section ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentSelection == section ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    if currentSelection == section {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(subsections(for: section)) { subsection in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        activeSubsectionID = subsection.id
                                        scrollRequestID = subsection.id
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: subsection.symbol)
                                            .font(.caption)
                                            .frame(width: 14)
                                        Text(subsection.title)
                                            .font(.caption.weight(.medium))
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(activeSubsectionID == subsection.id ? Color.accentColor : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(activeSubsectionID == subsection.id ? Color.accentColor.opacity(0.14) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 18)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: currentSelection)
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Label("Back to Torrents", systemImage: "chevron.left")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(.ultraThinMaterial)
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label(currentSelection.title, systemImage: currentSelection.symbol)
                    .font(.largeTitle.weight(.semibold))
                Text(sectionDescription(currentSelection))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            Group {
                switch currentSelection {
                case .general:
                    GeneralSettingsTab(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID)
                case .downloads:
                    DownloadsSettingsTab(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID)
                case .appearance:
                    AppearanceSettingsTab(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID)
                case .integration:
                    IntegrationSettingsTab(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Binding var activeSubsectionID: String?
    @Binding var scrollRequestID: String?
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var appUpdater: AppUpdater
    @State private var confirmResetCleanup = false

    var body: some View {
        SettingsScrollLayout(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID) {
            SettingsCard(
                title: "Behaviour",
                symbol: "slider.horizontal.3",
                subtitle: "Choose what swiftTorrent does automatically while downloads finish and move around the app."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-cleanup when download completes", isOn: $settings.autoCleanupEnabled)
                        .help("Automatically move completed downloads to their destination folders.")

                    Toggle("Filter non-media files automatically", isOn: $settings.autoFilterNonMediaFiles)
                        .help("Marks non-media files like exe, iso, and other junk as unwanted while still allowing video and subtitle files such as mkv, mp4, m4v, and srt.")
                }
            }
            .id("general.behaviour")
            .trackedSection(id: "general.behaviour")

            SettingsCard(
                title: "Maintenance",
                symbol: "wrench.and.screwdriver",
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
            .id("general.maintenance")
            .trackedSection(id: "general.maintenance")

            SettingsCard(
                title: "Updates",
                symbol: "arrow.triangle.2.circlepath",
                subtitle: "Sparkle checks the GitHub-hosted appcast for new releases. The feed URL and public key must already be configured in the app target."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Update Channel", systemImage: appUpdater.selectedChannel.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appUpdater.selectedChannel == .beta ? .orange : .secondary)

                        Picker("Update Channel", selection: Binding(
                            get: { appUpdater.selectedChannel },
                            set: { appUpdater.setUpdateChannel($0) }
                        )) {
                            ForEach(AppUpdater.UpdateChannel.allCases) { channel in
                                Text(channel.label).tag(channel)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Software updates")
                            Text(appUpdater.isConfigured
                                 ? "Checks Sparkle updates from the selected feed."
                                 : "Set SUFeedURL and SUPublicEDKey to enable Sparkle updates.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Check Now") { appUpdater.checkForUpdates() }
                            .buttonStyle(.bordered)
                            .disabled(!appUpdater.canCheckForUpdates)
                    }

                    HStack(spacing: 14) {
                        SettingsHint(title: "Feed", detail: appUpdater.feedURLString.isEmpty ? "Not configured" : appUpdater.feedURLString)
                        SettingsHint(title: "Public Key", detail: appUpdater.hasPublicKey ? "Installed" : "Missing")
                    }

                    if appUpdater.selectedChannel == .beta {
                        Label("Beta channel is enabled. Updates will come from the beta appcast feed.", systemImage: "flask.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .id("general.updates")
            .trackedSection(id: "general.updates")
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
    @Binding var activeSubsectionID: String?
    @Binding var scrollRequestID: String?
    @ObservedObject private var settings = AppSettings.shared
    @State private var errorText: String?
    @State private var newCategoryID = ""
    @State private var newCategoryTitle = ""
    @State private var newCategorySymbol = "tag"

    var body: some View {
        SettingsScrollLayout(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID) {
            SettingsCard(
                title: "Default Location",
                symbol: "folder",
                subtitle: "Where new torrents are saved while they are downloading."
            ) {
                folderRow(label: "Download folder",
                          systemImage: "arrow.down.circle",
                          url: settings.resolvedDownloadURL,
                          fallbackPath: settings.downloadPathForDisplay) {
                    pickFolder { url in try settings.setDownloadURL(url) }
                }
            }
            .id("downloads.default")
            .trackedSection(id: "downloads.default")

            SettingsCard(
                title: "Queue",
                symbol: "line.3.horizontal.decrease.circle",
                subtitle: "Torrents beyond this limit stay queued until an active slot becomes available."
            ) {
                VStack(alignment: .leading, spacing: 12) {
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

                    Divider()

                    Toggle("Auto-manage idle downloads", isOn: $settings.autoManageIdleDownloads)

                    HStack {
                        Text("Pause after idle")
                        Spacer()
                        Stepper(value: $settings.idleDownloadMinutes, in: 1...120, step: 1) {
                            Text("\(settings.idleDownloadMinutes) min")
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .disabled(!settings.autoManageIdleDownloads)
                    }

                    HStack {
                        Text("Try resume every")
                        Spacer()
                        Stepper(value: $settings.idleResumeMinutes, in: 1...60, step: 1) {
                            Text("\(settings.idleResumeMinutes) min")
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .disabled(!settings.autoManageIdleDownloads)
                    }
                }
            }
            .id("downloads.queue")
            .trackedSection(id: "downloads.queue")

            SettingsCard(
                title: "Seeding",
                symbol: "dot.radiowaves.left.and.right",
                subtitle: "Automatically remove torrents from the list after seeding thresholds. Sonarr/Radarr-managed torrents are excluded."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-remove after seeding time", isOn: $settings.autoRemoveAfterSeedTime)

                    HStack {
                        Text("Seed time limit")
                        Spacer()
                        Stepper(value: $settings.seedTimeLimitMinutes, in: 5...10080, step: 5) {
                            Text("\(settings.seedTimeLimitMinutes) min")
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                        }
                        .disabled(!settings.autoRemoveAfterSeedTime)
                    }

                    Divider()

                    Toggle("Auto-remove after seed ratio", isOn: $settings.autoRemoveAfterSeedRatio)

                    HStack {
                        Text("Seed ratio limit")
                        Spacer()
                        Stepper(value: $settings.seedRatioLimit, in: 0.1...50, step: 0.1) {
                            Text(String(format: "%.1f", settings.seedRatioLimit))
                                .monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                        }
                        .disabled(!settings.autoRemoveAfterSeedRatio)
                    }
                }
            }
            .id("downloads.seeding")
            .trackedSection(id: "downloads.seeding")

            SettingsCard(
                title: "Destinations",
                symbol: "externaldrive",
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
            .id("downloads.destinations")
            .trackedSection(id: "downloads.destinations")

            SettingsCard(
                title: "Categories",
                symbol: "tag",
                subtitle: "Manage torrent categories."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
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
                        ForEach(settings.categoryDefinitionsForUI) { category in
                            CategoryEditorCard(category: category)
                        }
                    }
                }
            }
            .id("downloads.categories")
            .trackedSection(id: "downloads.categories")

            if let errorText {
                SettingsCard(title: "Folder Access", subtitle: "Folder selection failed.") {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    private func folderRow(label: String, systemImage: String, url: URL?, fallbackPath: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(shortenPath(url?.path ?? fallbackPath))
                    .font(.caption)
                    .foregroundStyle((url == nil && (fallbackPath?.isEmpty ?? true)) ? .tertiary : .secondary)
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

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Binding var activeSubsectionID: String?
    @Binding var scrollRequestID: String?
    @ObservedObject private var settings = AppSettings.shared
    private let metricModes: [(id: String, title: String)] = [
        ("both", "Download + Upload"),
        ("download", "Download Only"),
        ("upload", "Upload (Seeding) Only"),
        ("eta", "Total ETA")
    ]
    private let styleModes: [(id: String, title: String)] = [
        ("auto", "Auto"),
        ("colorful", "Colorful"),
        ("dark", "Dark"),
        ("tinted", "Tinted"),
        ("translucent", "Translucent")
    ]
    private let categorySecondaryModes: [(id: String, title: String)] = [
        ("none", "Off (Default)"),
        ("eta", "Category ETA"),
        ("size", "Category Size")
    ]

    var body: some View {
        SettingsScrollLayout(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID) {
            SettingsCard(
                title: "Dock Icon",
                symbol: "dock.rectangle",
                subtitle: "Control the live transfer telemetry shown on the Dock icon."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show active torrent count badge", isOn: $settings.dockShowActiveCountBadge)
                    Toggle("Show transfer overlay", isOn: $settings.dockShowTransferOverlay)

                    HStack {
                        Text("Overlay Content")
                        Spacer()
                        Picker("Overlay Content", selection: $settings.dockOverlayMetricMode) {
                            ForEach(metricModes, id: \.id) { mode in
                                Text(mode.title).tag(mode.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .disabled(!settings.dockShowTransferOverlay)
                    }

                    HStack {
                        Text("Overlay Style")
                        Spacer()
                        Picker("Overlay Style", selection: $settings.dockOverlayStyleMode) {
                            ForEach(styleModes, id: \.id) { mode in
                                Text(mode.title).tag(mode.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .disabled(!settings.dockShowTransferOverlay)
                    }

                    Text("The transfer overlay displays download and upload rates as stacked stats at the bottom of the Dock icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .id("appearance.dock")
            .trackedSection(id: "appearance.dock")

            SettingsCard(
                title: "Sidebar Category Labels",
                symbol: "list.bullet.rectangle",
                subtitle: "Show optional aggregate detail next to each category count."
            ) {
                HStack {
                    Text("Secondary Metric")
                    Spacer()
                    Picker("Secondary Metric", selection: $settings.categoryHeaderSecondaryMode) {
                        ForEach(categorySecondaryModes, id: \.id) { mode in
                            Text(mode.title).tag(mode.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
            .id("appearance.sidebar")
            .trackedSection(id: "appearance.sidebar")
        }
    }
}

// MARK: - Integration

private struct IntegrationSettingsTab: View {
    @Binding var activeSubsectionID: String?
    @Binding var scrollRequestID: String?
    @ObservedObject private var settings = AppSettings.shared
    @State private var webUIPortText: String = ""
    @State private var magnetClaimMessage: String?

    var body: some View {
        SettingsScrollLayout(activeSubsectionID: $activeSubsectionID, scrollRequestID: $scrollRequestID) {
            SettingsCard(
                title: "Web Interface",
                symbol: "network",
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
            .id("integration.web")
            .trackedSection(id: "integration.web")

            SettingsCard(
                title: "Sonarr & Radarr (RPC)",
                symbol: "lock.shield",
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
            .id("integration.rpc")
            .trackedSection(id: "integration.rpc")

            SettingsCard(
                title: "Magnet Links",
                symbol: "link",
                subtitle: "Make swiftTorrent the default app for magnet links opened from Safari or other apps."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Claim magnet links") {
                        claimMagnetLinks()
                    }
                    .buttonStyle(.borderedProminent)

                    if let magnetClaimMessage {
                        Text(magnetClaimMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .id("integration.magnet")
            .trackedSection(id: "integration.magnet")
        }
        .onAppear {
            if webUIPortText.isEmpty { webUIPortText = String(settings.webUIPort) }
        }
        .onChange(of: settings.webUIPort) {
            let s = String(settings.webUIPort)
            if webUIPortText != s { webUIPortText = s }
        }
    }

    private func claimMagnetLinks() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            magnetClaimMessage = "Unable to detect app bundle ID."
            return
        }

        let status = LSSetDefaultHandlerForURLScheme("magnet" as CFString, bundleID as CFString)
        magnetClaimMessage = status == noErr
            ? "swiftTorrent is now the default handler for magnet links."
            : "Could not claim magnet links (OSStatus \(status))."
    }
}

private struct SettingsScrollLayout<Content: View>: View {
    @Binding var activeSubsectionID: String?
    @Binding var scrollRequestID: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(24)
                .padding(.bottom, 220)
            }
            .coordinateSpace(name: "settingsScroll")
            .onChange(of: scrollRequestID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onPreferenceChange(SettingsSectionPositionPreferenceKey.self) { values in
                guard !values.isEmpty else { return }
                let sorted = values.sorted { abs($0.offset) < abs($1.offset) }
                activeSubsectionID = sorted.first?.id
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var symbol: String? = nil
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let symbol {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                } else {
                    Text(title)
                        .font(.headline)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

private struct SectionOffset: Equatable {
    let id: String
    let offset: CGFloat
}

private struct SettingsSectionPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [SectionOffset] = []
    static func reduce(value: inout [SectionOffset], nextValue: () -> [SectionOffset]) {
        value.append(contentsOf: nextValue())
    }
}

private struct TrackedSectionModifier: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SettingsSectionPositionPreferenceKey.self,
                    value: [SectionOffset(id: id, offset: geo.frame(in: .named("settingsScroll")).minY)]
                )
            }
        )
    }
}

private extension View {
    func trackedSection(id: String) -> some View {
        modifier(TrackedSectionModifier(id: id))
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
