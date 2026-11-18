import Foundation

/// A 3 × 3 × 3 sRGB lattice, indexed from black (0) to white (26).
enum CalibrationTarget {
    static let essentials = [26, 18, 6, 2, 24, 8, 20]
    static let refinements = [13, 21, 25, 15, 7, 17, 5, 11, 23, 19, 22, 9, 12, 3, 4, 1, 10, 14, 16]
    static let names = [
        "Black", "Navy", "Blue", "Dark green", "Teal", "Azure", "Green", "Spring green", "Cyan",
        "Maroon", "Purple", "Violet", "Olive", "Gray", "Periwinkle", "Chartreuse", "Mint", "Ice blue",
        "Red", "Rose", "Magenta", "Orange", "Salmon", "Orchid", "Yellow", "Pale yellow", "White"
    ]
    static let middle = 128.0 / 255

    static func color(_ index: Int) -> RGB {
        let levels = [0.0, middle, 1]
        return RGB(r: levels[index / 9], g: levels[index / 3 % 3], b: levels[index % 3])
    }
}

struct ColorCalibration: Codable, Equatable {
    var enabled = true
    var matches: [Int: RGB] = [:]

    func output(for target: Int) -> RGB {
        if target == 0 { return .black }
        if matches[target] != nil { return node(target) }
        let reference = CalibrationTarget.color(target)
        return ColorLUT.interpolate(reference, stride: 2, node: node)
    }

    private func node(_ target: Int) -> RGB {
        guard target != 0, let match = matches[target] else { return CalibrationTarget.color(target) }
        return RGB(r: min(1, max(0, match.r)), g: min(1, max(0, match.g)), b: min(1, max(0, match.b)))
    }
}

struct ColorLUT {
    private let nodes: [RGB]

    init(_ profile: ColorCalibration) {
        nodes = profile.enabled && !profile.matches.isEmpty ? (0..<27).map(profile.output) : []
    }

    func apply(to frame: [RGB]) -> [RGB] {
        guard !nodes.isEmpty else { return frame }
        return frame.map { Self.interpolate($0, stride: 1) { nodes[$0] } }
    }

    /// Split each cube along its gray diagonal so neutral ramps follow the white match.
    fileprivate static func interpolate(_ input: RGB, stride: Int, node: (Int) -> RGB) -> RGB {
        var origin = 0
        func axis(_ value: Double, _ offset: Int) -> (weight: Double, offset: Int) {
            let value = min(1, max(0, value))
            if stride == 2 { return (value, offset * 2) }
            let mid = CalibrationTarget.middle
            if value < mid { return (value / mid, offset) }
            origin += offset
            return ((value - mid) / (1 - mid), offset)
        }
        var x = axis(input.r, 9), y = axis(input.g, 3), z = axis(input.b, 1)
        if x.weight < y.weight { swap(&x, &y) }
        if y.weight < z.weight { swap(&y, &z) }
        if x.weight < y.weight { swap(&x, &y) }
        let a = node(origin), b = node(origin + x.offset)
        let c = node(origin + x.offset + y.offset), d = node(origin + x.offset + y.offset + z.offset)
        func channel(_ key: KeyPath<RGB, Double>) -> Double {
            let result = (1 - x.weight) * a[keyPath: key] + (x.weight - y.weight) * b[keyPath: key]
                + (y.weight - z.weight) * c[keyPath: key] + z.weight * d[keyPath: key]
            return min(1, max(0, result))
        }
        return RGB(r: channel(\.r), g: channel(\.g), b: channel(\.b))
    }
}
