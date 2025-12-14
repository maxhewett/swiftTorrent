//
//  TorrentWindOverlay.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI
import Foundation

struct TorrentWindOverlay: View {
    let t: TorrentRow

    private var mode: Mode? {
        if t.isPaused { return nil }
        if t.state == 3 && t.downBps > 0 { return .downloading }
        if t.state == 5 && (t.upBps > 0 || t.isSeeding) { return .seeding }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            if let mode {
                WindArrowsField(
                    direction: mode.direction,
                    speed: mode.speed
                )
                .opacity(0.40)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
    }

    enum Mode {
        case downloading
        case seeding

        var direction: WindArrowsField.Direction {
            self == .downloading ? .down : .up
        }

        var speed: Double {
            self == .downloading ? 1.0 : 1.15
        }
    }
}
