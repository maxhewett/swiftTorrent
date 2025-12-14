//
//  WindArrowsField.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import SwiftUI

struct WindArrowsField: View {
    enum Direction { case up, down }

    let direction: Direction
    let speed: Double

    struct Particle: Hashable {
        let x: CGFloat
        let y: CGFloat
        let alpha: Double
        let scale: CGFloat
        let drift: CGFloat
        let wobbleAmp: CGFloat
        let wobbleFreq: CGFloat
        let wobblePhase: CGFloat
    }

    @State private var seed: UInt64 = 0
    @State private var particles: [Particle] = []
    @State private var lastSize: CGSize = .zero

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // If the row size changes (first layout / dynamic type / resize), rebuild particles once.
                if size != lastSize || particles.isEmpty {
                    // Canvas is not a great place to mutate @State; defer rebuild to next runloop.
                    DispatchQueue.main.async {
                        rebuildParticles(for: size)
                    }
                }

                guard !particles.isEmpty else { return }

                let symbolName = (direction == .down) ? "arrow.down" : "arrow.up"
                let symbolText = Text(Image(systemName: symbolName))
                    .font(.system(size: 13, weight: .bold))
                let resolved = context.resolve(symbolText)

                let t = timeline.date.timeIntervalSinceReferenceDate
                let dir: CGFloat = (direction == .down) ? 1 : -1

                for p in particles {
                    // Continuous motion: pixels per second (scaled by row height)
                    let pixelsPerSecond = (p.drift * 0.35 * CGFloat(speed)) * size.height
                    var y = p.y + dir * CGFloat(t) * pixelsPerSecond

                    // Wrap y smoothly
                    y = y.truncatingRemainder(dividingBy: size.height)
                    if y < 0 { y += size.height }

                    // horizontal wobble (already continuous)
                    let wobble = p.wobbleAmp * sin(CGFloat(t) * p.wobbleFreq + p.wobblePhase)
                    let x = p.x + wobble

                    var c = context
                    c.opacity = p.alpha
                    c.scaleBy(x: p.scale, y: p.scale)
                    c.draw(resolved, at: CGPoint(x: x, y: y), anchor: .center)
                }
            }
        }
        .onAppear {
            if seed == 0 {
                seed = UInt64.random(in: 1...UInt64.max)
            }
        }
    }

    private func rebuildParticles(for size: CGSize) {
        lastSize = size
        guard size.width > 0, size.height > 0 else {
            particles = []
            return
        }

        // Density knob: lower = more dense
        // This is still “busy” but way cheaper than regenerating every frame.
        let count = max(45, Int(size.width / 9))

        var rng = SeededGenerator(seed: seed == 0 ? 1 : seed)
        var out: [Particle] = []
        out.reserveCapacity(count)

        for _ in 0..<count {
            let x = CGFloat.random(in: 0...size.width, using: &rng)
            let y = CGFloat.random(in: 0...size.height, using: &rng)

            let alpha = Double.random(in: 0.10...0.32, using: &rng)
            let scale = CGFloat.random(in: 0.60...1.20, using: &rng)

            // Drift is “fractions of row height per cycle”
            let drift = CGFloat.random(in: 0.55...1.35, using: &rng)

            let wobbleAmp = CGFloat.random(in: 0...10, using: &rng)
            let wobbleFreq = CGFloat.random(in: 0.8...1.8, using: &rng)
            let wobblePhase = CGFloat.random(in: 0...(2 * .pi), using: &rng)

            out.append(.init(
                x: x,
                y: y,
                alpha: alpha,
                scale: scale,
                drift: drift,
                wobbleAmp: wobbleAmp,
                wobbleFreq: wobbleFreq,
                wobblePhase: wobblePhase
            ))
        }

        particles = out
    }
}
