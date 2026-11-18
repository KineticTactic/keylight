import Foundation

// Core75 per-key VIA extension. Only volatile lighting setters are used.
enum VIA {
    static let count = 81 // The firmware reserves LED 81 for the encoder indicator.
    static let mode: [UInt8] = [3, 2]
    static let brightness: [UInt8] = [3, 1]

    static func channels(_ color: RGB) -> (UInt8, UInt8, UInt8) {
        let hi = max(color.r, color.g, color.b), low = min(color.r, color.g, color.b)
        let delta = hi - low
        var h = 0.0
        if delta > 0 {
            if hi == color.r { h = (color.g - color.b) / delta }
            else if hi == color.g { h = 2 + (color.b - color.r) / delta }
            else { h = 4 + (color.r - color.g) / delta }
            if h < 0 { h += 6 }
        }
        return (UInt8((h / 6 * 255).rounded()), UInt8((hi == 0 ? 0 : delta / hi * 255).rounded()),
                UInt8((hi * 255).rounded()))
    }

    static func ranges() -> [[UInt8]] {
        [1, 2].flatMap { type -> [[UInt8]] in
            let maximum = type == 1 ? 13 : 27
            return stride(from: 0, to: count, by: maximum).map { start in
                [0, UInt8(type), UInt8(start), UInt8(min(maximum, count - start))]
            }
        }
    }

    static func frames(_ colors: [RGB], previous: [RGB]) -> [[UInt8]] {
        let hsv = colors.prefix(count).map(channels)
        let old = previous.prefix(count).map(channels)
        return ranges().compactMap { header in
            let start = Int(header[2]), end = start + Int(header[3])
            // Chroma and intensity are independent VIA controls. A brightness
            // pulse can update the whole board with three intensity reports.
            if old.count == hsv.count && (start..<end).allSatisfy({ index in
                let a = old[index], b = hsv[index]
                return header[1] == 1 ? (a.0 == b.0 && a.1 == b.1) : a.2 == b.2
            }) { return nil }
            let values = hsv[start..<end].flatMap { h, s, v -> [UInt8] in header[1] == 1 ? [h, s] : [v] }
            return Wire.report([7] + header + values)
        }
    }
}
