import Foundation

struct RGB: Codable, Equatable {
    var r, g, b: Double
    static let black = RGB(r: 0, g: 0, b: 0)
    func mix(_ other: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
    var bytes: [UInt8] { [r, g, b].map { UInt8((255 * min(1, max(0, $0))).rounded()) } }
}

enum Effect: String, Codable, CaseIterable {
    case solid = "Solid", wave = "Wave", screen = "Screen ambience", bass = "Bass pulse"
    case drum = "Drum hit", spectrum = "Frequency bands", breathe = "Breathe", ripple = "Radial ripple"

    case hiHat = "Hi-hat"

    case aurora = "Aurora curtains", meteors = "Meteor trails", embers = "Ember drift"
    case tempo = "Tempo wave", towers = "Equalizer bars", cinema = "Screen wash"
    case bloom = "Bass echo"
    case ensemble = "Regional glide", orbits = "Orbiting lights"

    var usesMix: Bool { self == .ensemble || self == .orbits }
    var followsTempo: Bool { self == .tempo || usesMix }

    var usesScreen: Bool { self == .screen || self == .cinema }
    var usesBands: Bool { self == .spectrum || self == .towers }
    var usesAudio: Bool { self == .hiHat || self == .drum || usesBands || self == .bass || followsTempo || self == .bloom }
    var hasMotion: Bool { [.wave, .breathe, .ripple, .aurora, .meteors, .embers].contains(self) }
}

struct AudioResponse: Codable, Equatable {
    var gain = 1.0
    var fade = 0.22
    var smoothingSeconds: Double?
    var smoothing: Double {
        get { smoothingSeconds ?? 0 }
        set { smoothingSeconds = newValue }
    }
}
struct Layer: Codable, Identifiable, Equatable {
    var id = UUID()
    var effect: Effect = .wave
    var color = RGB(r: 0.37, g: 0.91, b: 0.76)
    var secondary = RGB(r: 0.52, g: 0.29, b: 0.91)
    // Older scene files contain only the two endpoint colors.
    private(set) var middleColor: RGB?
    var middle: RGB {
        get { middleColor ?? RGB(r: 0, g: 0.8, b: 1) }
        set { middleColor = newValue }
    }
    var speed = 0.35
    var opacity = 1.0
    var beatsPerWave: Int?
    var cycleBeats: Int { max(1, beatsPerWave ?? (effect == .ensemble ? 16 : effect == .orbits ? 8 : 4)) }
    var mixSmoothing: Double { max(0.4, audio.smoothingSeconds ?? (effect == .ensemble ? 0.95 : 0.8)) }
    var ensembleReactivity: Double?
    var reactivity: Double {
        get { ensembleReactivity ?? 1.15 }
        set { ensembleReactivity = newValue }
    }
    var silenceColor: RGB?
    var silenceColorEnabled: Bool?
    var usesSilenceColor: Bool {
        get { silenceColor != nil && silenceColorEnabled != false }
        set {
            if newValue && silenceColor == nil { silenceColor = color }
            silenceColorEnabled = newValue
        }
    }
    var echoDirection: EchoDirection?
    // Optional backing keeps scenes saved by version 0.1 readable.
    var tuning: [String: [FrequencyBand]]?
    var audioModulation: Bool?
    var response: AudioResponse?
    var audio: AudioResponse {
        get { response ?? AudioResponse() }
        set { response = newValue }
    }
    // nil covers the whole board. An empty set covers no keys.
    var keys: Set<Int>? = nil

    static var numberRowHiHat: Layer {
        Layer(effect: .hiHat, color: RGB(r: 0.94, g: 0.67, b: 1),
              response: AudioResponse(gain: 1, fade: 0.14), keys: Board.numberRow)
    }
}
struct LightingScene: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Untitled mode"
    var layers = [Layer()]
    var brightness = 0.7
    var drumPresetRevision: Int?
}

extension LightingScene {
    static let drumSceneID = FactoryMode.percussion.id
    static var drumScene: LightingScene {
        let spectrum = Layer(effect: .spectrum, color: RGB(r: 0, g: 0.87, b: 0.78),
                             secondary: RGB(r: 0.74, g: 0.28, b: 1), keys: Board.interior)
        let drums = Layer(effect: .drum, color: RGB(r: 1, g: 0, b: 0), keys: Board.perimeter)
        var scene = LightingScene(id: drumSceneID, name: FactoryMode.percussion.title, layers: [spectrum, drums])
        scene.upgradeDrumPreset()
        return scene
    }

    mutating func upgradeDrumPreset() {
        guard id == Self.drumSceneID, (drumPresetRevision ?? 0) < 1 else { return }
        if let index = layers.firstIndex(where: { $0.effect == .spectrum }) {
            let mask = layers[index].keys ?? Set(Board.keys.map(\.id))
            layers[index].keys = mask.subtracting(Board.numberRow)
            if layers[index].audio.smoothingSeconds == nil { layers[index].audio.smoothing = 0.20 }
        }
        if !layers.contains(where: { $0.effect == .hiHat }) {
            layers.append(.numberRowHiHat)
        }
        drumPresetRevision = 1
    }
}

struct Signals {
    var quietDuration: Double?
    var silenceBlend = 0.0
    var screen = Array(repeating: RGB.black, count: Board.keys.count)
    var audio: [UUID: AudioReading] = [:]
    var meter = SpectrumMeter.silent
    var rhythmBeats: [UUID: Double] = [:]
}

enum EffectEngine {
    static func render(_ scene: LightingScene, time: Double, signals: Signals, smoothedBands: [UUID: [Double]] = [:]) -> [RGB] {
        let wash = scene.layers.contains { $0.effect == .cinema } ? ModeEffects.screenColumns(signals.screen) : []
        var fronts: [UUID: [EchoFront]] = [:]
        for layer in scene.layers where layer.effect == .bloom {
            fronts[layer.id] = signals.audio[layer.id]?.echoFronts(for: layer)
        }
        return Board.keys.map { key in
            let x = (key.x + key.width / 2) / Board.width
            let y = (key.y + 0.5) / Board.height
            var pixel = RGB.black
            for layer in scene.layers where layer.keys?.contains(key.id) ?? true {
                var alpha = layer.opacity
                let ink: RGB
                let input = signals.audio[layer.id]
                switch layer.effect {
                case .aurora: ink = ModeEffects.aurora(x: x, y: y, time: time, layer: layer)
                case .meteors: ink = ModeEffects.meteor(x: x, row: Int(key.y), time: time, layer: layer)
                case .embers: ink = ModeEffects.embers(x: x, y: y, time: time, layer: layer)
                case .cinema:
                    let position = min(4, max(0, x * 5 - 0.5))
                    let lo = Int(position)
                    let diffuse = wash[lo].mix(wash[min(4, lo + 1)], position - Double(lo))
                    ink = diffuse.mix(signals.screen[key.id], 0.24)
                case .bloom:
                    let distance = (layer.echoDirection ?? .outward).distance(x: x, y: y)
                    ink = layer.color.mix(layer.secondary, distance)
                    let level = fronts[layer.id]?.reduce(0.0) { max($0, $1.intensity(at: distance)) }
                    alpha *= level ?? 0
                case .ensemble, .orbits:
                    let beats = signals.rhythmBeats[layer.id] ?? time * 1.25
                    let phase = 2 * Double.pi * beats / Double(layer.cycleBeats)
                    let mix = smoothedBands[layer.id] ?? input?.levels ?? [0, 0, 0, 0]
                    if layer.effect == .ensemble {
                        ink = ModeEffects.ensemble(key: key, x: x, y: y, phase: phase, mix: mix, layer: layer)
                    } else {
                        ink = ModeEffects.orbits(x: x, y: y, phase: phase, mix: mix, layer: layer)
                    }
                case .tempo:
                    let beats = signals.rhythmBeats[layer.id] ?? time * 1.25
                    let phase = beats / Double(layer.cycleBeats)
                    let blend = (1 + cos(2 * .pi * (x * 0.9 + 0.18 * y - phase))) / 2
                    ink = layer.color.mix(layer.secondary, blend)
                case .towers:
                    let levels = smoothedBands[layer.id] ?? input?.levels
                    let column = min(FrequencyBand.towerBands.count - 1, Int(x * Double(FrequencyBand.towerBands.count)))
                    let amplitude = levels.flatMap { $0.indices.contains(column) ? $0[column] : nil } ?? 0
                    let level = min(1, amplitude * layer.audio.gain)
                    let fill = min(1, max(0, level * 6 - Double(5 - Int(key.y))))
                    ink = layer.color.mix(layer.secondary, 1 - y)
                    alpha *= fill
                case .solid: ink = layer.color
                case .wave:
                    let phase = (key.x + key.width / 2) / Board.width - time * layer.speed
                    ink = layer.color.mix(layer.secondary, (cos(phase * .pi * 2) + 1) / 2)
                case .breathe:
                    ink = layer.color
                    alpha *= (1 + cos(time * layer.speed * 2 * .pi)) / 2
                case .ripple:
                    let radius = hypot(key.x + key.width / 2 - Board.width / 2, key.y + 0.5 - Board.height / 2)
                    ink = layer.color.mix(layer.secondary, (1 + cos((radius / 5 - time * layer.speed) * 2 * .pi)) / 2)
                case .drum, .hiHat:
                    ink = layer.color
                    let age = input?.age ?? .infinity
                    let strength = input?.strength ?? 0
                    let tail = max(0, 1 - age / max(0.01, layer.audio.fade))
                    alpha *= min(1, layer.audio.gain * strength) * tail * tail
                case .spectrum:
                    let position = (key.x + key.width / 2) / Board.width
                    let band = min(3, Int(position * 4))
                    if position <= 0.5 {
                        ink = layer.color.mix(layer.middle, position * 2)
                    } else {
                        ink = layer.middle.mix(layer.secondary, (position - 0.5) * 2)
                    }
                    let levels = smoothedBands[layer.id] ?? input?.levels
                    alpha *= min(1, (levels?[band] ?? 0) * layer.audio.gain)
                case .screen: ink = signals.screen[key.id]
                case .bass:
                    ink = layer.color
                    alpha *= min(1, (input?.levels[0] ?? 0) * layer.audio.gain)
                }
                if !layer.effect.usesAudio && layer.audioModulation == true {
                    alpha *= min(1, (input?.levels[0] ?? 0) * layer.audio.gain)
                }
                let normal = pixel.mix(ink, alpha)
                if signals.silenceBlend > 0, layer.usesSilenceColor, let rest = layer.silenceColor {
                    pixel = normal.mix(pixel.mix(rest, layer.opacity), signals.silenceBlend)
                } else {
                    pixel = normal
                }
            }
            return RGB.black.mix(pixel, scene.brightness)
        }
    }
}
