//
//  SettingsView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var errorText: String? = nil

    var body: some View {
        Form {
            Section("Automation") {
                Toggle("Auto-cleanup when download completes", isOn: $settings.autoCleanupEnabled)

                Button("Reset cleanup history (allow re-cleaning completed torrents)") {
                    settings.resetCleaned()
                }
            }

            Section("Destinations") {
                destinationRow(
                    title: "Movies folder",
                    url: settings.moviesURL()
                ) {
                    FolderPicker.pickFolder { url in
                        guard let url else { return }
                        Task { @MainActor in
                            do {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }

                                try settings.setMoviesURL(url)

                                // sanity: force read-back
                                _ = settings.moviesURL()

                                errorText = nil
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    }
                }

                destinationRow(
                    title: "TV folder",
                    url: settings.tvURL()
                ) {
                    FolderPicker.pickFolder { url in
                        guard let url else { return }
                        Task { @MainActor in
                            do {
                                let access = url.startAccessingSecurityScopedResource()
                                defer { if access { url.stopAccessingSecurityScopedResource() } }

                                try settings.setTVURL(url)

                                // sanity: force read-back
                                _ = settings.tvURL()

                                errorText = nil
                            } catch {
                                errorText = error.localizedDescription
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }

                // Optional debugging line (remove later)
                Text("Movies bookmark bytes: \(settings.moviesBookmarkData?.count ?? 0) • TV: \(settings.tvBookmarkData?.count ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
