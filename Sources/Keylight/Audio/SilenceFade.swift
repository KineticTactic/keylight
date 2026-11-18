import Foundation

struct SilenceFade {
    private var blend = 0.0

    mutating func update(quietDuration: Double?, delta: Double) -> Double {
        guard let quietDuration else { blend = 0; return 0 }
        let progress = min(1, max(0, (quietDuration - 1.5) / 1.8))
        let target = progress * progress * (3 - 2 * progress)
        if target >= blend { blend = target }
        else { blend = target + (blend - target) * exp(-max(0, delta) / 0.032) }
        if blend < 0.001 { blend = 0 }
        return blend
    }
}
