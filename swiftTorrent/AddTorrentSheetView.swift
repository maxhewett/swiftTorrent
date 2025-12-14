//
//  AddTorrentSheetView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct AddTorrentSheetView: View {
    var onAdd: (_ magnet: String, _ savePath: String, _ category: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var magnet = ""
    @State private var savePath = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                                   ?? (NSHomeDirectory() + "/Downloads"))
    @State private var category: CategoryChoice = .tv

    enum CategoryChoice: String, CaseIterable, Identifiable {
        case tv = "tv"
        case movies = "movie"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .tv: return "TV"
            case .movies: return "Movies"
            }
        }
        var systemImage: String {
            switch self {
            case .tv: return "tv"
            case .movies: return "film"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Torrent")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Magnet link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $magnet)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Save path")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Save path…", text: $savePath)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Category", selection: $category) {
                    ForEach(CategoryChoice.allCases) { c in
                        Label(c.title, systemImage: c.systemImage).tag(c)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    let m = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
                    let p = savePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !m.isEmpty, !p.isEmpty else { return }

                    onAdd(m, p, category.rawValue)
                    dismiss()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 420)
    }
}
