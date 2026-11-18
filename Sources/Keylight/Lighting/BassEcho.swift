import Foundation

enum EchoDirection: String, Codable, CaseIterable {
    case outward = "Out from spacebar"
    case inward = "In toward spacebar"
    case right = "Left to right"
    case left = "Right to left"
    case down = "Top to bottom"
    case up = "Bottom to top"

    func distance(x: Double, y: Double) -> Double {
        // Normalize key centers so even the last row lights before the wave dies.
        let horizontal = (x * Board.width - 0.5) / (Board.width - 1)
        let vertical = (y * Board.height - 0.5) / (Board.height - 1)
        switch self {
        case .right: return horizontal
        case .left: return 1 - horizontal
        case .down: return vertical
        case .up: return 1 - vertical
        case .outward, .inward:
            let dx = x * Board.width - 6.875 // center of the spacebar
            let dy = (1 - vertical) * (Board.height - 1)
            let radial = hypot(dx, dy) / hypot(Board.width - 0.5 - 6.875, Board.height - 1)
            return self == .outward ? radial : 1 - radial
        }
    }
}

struct EchoHit {
    let onset: Double
    let strength: Double
}

struct EchoFront {
    let position: Double
    let amplitude: Double

    init?(age: Double, lifetime: Double, strength: Double, gain: Double) {
        guard age >= 0, age < lifetime else { return nil }
        let progress = age / lifetime
        position = progress * 1.24
        amplitude = min(1, strength * gain) * (1 - 0.52 * progress)
    }

    func intensity(at distance: Double) -> Double {
        let offset = (distance - position) / 0.10
        return amplitude * exp(-offset * offset)
    }
}

extension AudioReading {
    func echoFronts(for layer: Layer) -> [EchoFront] {
        let lifetime = max(0.06, layer.audio.fade)
        guard let latest = echoHits.last else { return [] }
        // 'age' includes the partial FFT window and elapsed time since capture.
        // All earlier hits share that clock, even if several arrived in one callback.
        return echoHits.compactMap { hit in
            EchoFront(age: age + (latest.onset - hit.onset), lifetime: lifetime,
                      strength: hit.strength, gain: layer.audio.gain)
        }
    }
}
