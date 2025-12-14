//
//  SettingsView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("General") {
                Text("Settings coming soon…")
                    .foregroundStyle(.secondary)
            }

            Section("Post-download cleanup") {
                Toggle("Enable cleanup rules", isOn: .constant(false))
                    .disabled(true)

                Text("We’ll add rules like: move/rename/unzip/permissions/seed-until/etc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 520)
    }
}
