//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @StateObject private var engine = TorrentEngine()

    @State private var selectedTorrentID: String?
    @State private var magnet = ""
    @State private var savePath = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                                   ?? (NSHomeDirectory() + "/Downloads"))
    @State private var category = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Magnet link…", text: $magnet)
                    .textFieldStyle(.roundedBorder)

                TextField("Save path…", text: $savePath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                TextField("Category…", text: $category)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Button("Add") {
                    let c = category.trimmingCharacters(in: .whitespacesAndNewlines)
                    errorText = engine.addMagnet(magnet, savePath: savePath, category: c.isEmpty ? nil : c)
                }
                .disabled(magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }

            HSplitView {
                List(selection: $selectedTorrentID) {
                    ForEach(engine.torrents) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(t.name).lineLimit(1)
                                    Spacer()
                                    if let cat = t.category, !cat.isEmpty {
                                        Text(cat)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                ProgressView(value: t.progress)
                                    .animation(nil, value: t.progress)
                            }

                            Spacer()

                            Text(stateLabel(t.state))
                                .frame(width: 100, alignment: .leading)
                                .foregroundStyle(.secondary)

                            Text("\(t.peers)p/\(t.seeds)s")
                                .frame(width: 70, alignment: .trailing)
                                .foregroundStyle(.secondary)

                            Text("↓ \(formatBps(t.downBps))")
                                .frame(width: 110, alignment: .trailing)
                                .foregroundStyle(.secondary)

                            Text("↑ \(formatBps(t.upBps))")
                                .frame(width: 110, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                        .tag(t.id)
                    }
                }
                .frame(minWidth: 650)

                if let id = selectedTorrentID,
                   let torrent = engine.torrents.first(where: { $0.id == id }) {
                    TorrentInspectorView(torrent: torrent, engine: engine)
                        .frame(minWidth: 320, idealWidth: 360)
                } else {
                    VStack {
                        Text("Select a torrent")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .frame(minWidth: 320, idealWidth: 360)
                }
            }
        }
        .padding()
        .frame(minWidth: 1050, minHeight: 560)
    }

    private func formatBps(_ bps: Int) -> String {
        let kb = Double(bps) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024.0)
    }

    private func stateLabel(_ s: Int) -> String {
        switch s {
        case 0: return "Queued"
        case 1: return "Checking"
        case 2: return "DL metadata"
        case 3: return "Downloading"
        case 4: return "Finished"
        case 5: return "Seeding"
        case 6: return "Allocating"
        case 7: return "Checking fast"
        default: return "State \(s)"
        }
    }
}
