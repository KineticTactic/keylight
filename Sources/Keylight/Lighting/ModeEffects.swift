import Foundation

enum ModeEffects {
    static func ensemble(key: Key, x: Double, y: Double, phase: Double, mix: [Double], layer: Layer) -> RGB {
        let base: RGB, accent: RGB, weight: Double, angle: Double
        if Board.numberRow.contains(key.id) {
            (base, accent, weight) = (layer.secondary, layer.middle, mix[2])
            angle = phase * 0.75 - 2.4 * x
        } else if Board.perimeter.contains(key.id) {
            (base, accent, weight) = (layer.color, layer.secondary, mix[0])
            angle = phase + atan2(y - 0.5, x - 0.5)
        } else {
            (base, accent, weight) = (layer.middle, layer.color, mix[1])
            angle = 0.5 * phase + 3.8 * x + 1.6 * y
        }
        // Let the smoothed band sweep the highlight through its region.
        // A dim resting color makes the movement visible at ordinary levels.
        let energy = min(1, max(0, weight - 0.10) * 1.5 * layer.reactivity)
        let drift = (1 + cos(angle + 3.5 * energy)) / 2
        let shade = base.mix(accent, 0.06 + 0.52 * drift * energy)
        let light = 0.05 + 0.09 * drift + energy * (0.69 + 0.17 * drift)
        return RGB.black.mix(shade, light)
    }

    static func orbits(x: Double, y: Double, phase: Double, mix: [Double], layer: Layer) -> RGB {
        // The second light completes three laps for every four of the first.
        func pool(_ cx: Double, _ cy: Double, width: Double) -> Double {
            let dx = (x - cx) / width, dy = (y - cy) / 0.40
            return exp(-dx * dx - dy * dy)
        }
        let first = pool(0.5 + 0.36 * cos(phase), 0.5 + 0.32 * sin(phase), width: 0.24 + 0.12 * mix[0])
        let secondAngle = 1.6 - 0.75 * phase
        let second = pool(0.5 + 0.34 * cos(secondAngle), 0.5 + (0.21 + 0.15 * mix[2]) * sin(secondAngle), width: 0.29)
        let bed = RGB.black.mix(layer.middle, 0.30)
        return bed.mix(layer.color, first).mix(layer.secondary, second * (1 - 0.35 * first))
    }

    static func aurora(x: Double, y: Double, time: Double, layer: Layer) -> RGB {
        let t = time * layer.speed
        let fold = 0.51 + 0.28 * sin(x * 5 + t) + 0.12 * sin(x * 10 - t * 0.72)
        let veil = exp(-pow((y - fold) / 0.28, 2))
        let fringe = exp(-pow((y - fold - 0.24) / 0.18, 2))
        let sky = RGB.black.mix(layer.secondary, 0.11)
        return sky.mix(layer.secondary, fringe * 0.88).mix(layer.color, veil * (0.72 + 0.26 * cos(x * 8 - t)))
    }

    static func meteor(x: Double, row: Int, time: Double, layer: Layer) -> RGB {
        let travel = time * layer.speed * (0.19 + 0.018 * Double(row)) + Double(row) * 0.317
        let head = (travel - floor(travel)) * 1.7 - 0.08
        let offset = head - (row.isMultiple(of: 2) ? x : 1 - x)
        let trail = offset >= 0 ? exp(-offset * 8) : exp(-pow(offset / 0.043, 2))
        let ink = layer.secondary.mix(layer.color, min(1, trail * trail))
        return RGB.black.mix(layer.secondary, 0.045).mix(ink, trail)
    }

    static func embers(x: Double, y: Double, time: Double, layer: Layer) -> RGB {
        let t = time * layer.speed
        let heat = 0.5 + 0.25 * sin(11 * x + 4 * y + t) + 0.25 * sin(6 * x - 8 * y - 0.62 * t)
        let intensity = min(1, (0.3 + 0.7 * y) * (0.2 + 1.15 * heat))
        return RGB.black.mix(layer.color.mix(layer.secondary, intensity * intensity), intensity)
    }

    // A luminance-weighted wash lets a bright subject carry its color across
    // neighboring keys, while black letterbox bars contribute very little.
    static func screenColumns(_ colors: [RGB]) -> [RGB] {
        var sums = Array(repeating: RGB.black, count: 5)
        var weights = Array(repeating: 0.0, count: 5)
        for key in Board.keys {
            let column = min(4, Int((key.x + key.width / 2) / Board.width * 5))
            let c = colors[key.id]
            let weight = 0.08 + max(c.r, c.g, c.b)
            sums[column].r += c.r * weight
            sums[column].g += c.g * weight
            sums[column].b += c.b * weight
            weights[column] += weight
        }
        return zip(sums, weights).map { RGB(r: $0.r / $1, g: $0.g / $1, b: $0.b / $1) }
    }
}
