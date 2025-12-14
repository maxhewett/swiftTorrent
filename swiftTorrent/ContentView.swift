//
//  ContentView.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = TorrentEngine()

    @State private var magnet = ""
    @State private var savePath = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                                   ?? (NSHomeDirectory() + "/Downloads"))
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Magnet link…", text: $magnet)
                    .textFieldStyle(.roundedBorder)

                TextField("Save path…", text: $savePath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                Button("Add") {
                    errorText = engine.addMagnet(magnet, savePath: savePath)
                }
                .disabled(magnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }

            List(engine.torrents) { t in
                HStack {
                    VStack(alignment: .leading) {
                        Text(t.name).lineLimit(1)
                        ProgressView(value: t.progress)
                            .animation(nil, value: t.progress) // stops the “restart swoosh”
                    }

                    Spacer()

                    Text(stateLabel(t.state))
                        .frame(width: 100, alignment: .leading)

                    Text("\(t.peers)p/\(t.seeds)s")
                        .frame(width: 70, alignment: .trailing)

                    Text("↓ \(formatBps(t.downBps))")
                        .frame(width: 110, alignment: .trailing)

                    Text("↑ \(formatBps(t.upBps))")
                        .frame(width: 110, alignment: .trailing)
                }
            }
        }
        .padding()
        .frame(minWidth: 900, minHeight: 500)
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
