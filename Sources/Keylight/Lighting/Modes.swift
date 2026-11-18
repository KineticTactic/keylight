import Foundation

enum FactoryMode: String, CaseIterable {
    case tempo = "490CA782-1EED-4AAD-828F-46C870FAA301"
    case ensemble = "490CA782-1EED-4AAD-828F-46C870FAA308"
    case orbits = "490CA782-1EED-4AAD-828F-46C870FAA309"
    case percussion = "3360D7CD-7453-4609-ABF2-645879A49566"
    case towers = "490CA782-1EED-4AAD-828F-46C870FAA302"
    case bloom = "490CA782-1EED-4AAD-828F-46C870FAA307"
    case aurora = "490CA782-1EED-4AAD-828F-46C870FAA303"
    case meteor = "490CA782-1EED-4AAD-828F-46C870FAA304"
    case ember = "490CA782-1EED-4AAD-828F-46C870FAA305"
    case cinema = "490CA782-1EED-4AAD-828F-46C870FAA306"

    var id: UUID { UUID(uuidString: rawValue)! }
    var title: String {
        switch self {
        case .ensemble: return "Velvet Ensemble"
        case .orbits: return "Twin Orbits"
        case .tempo: return "Tempo Tide"
        case .percussion: return "Drums, Hats & Spectrum"
        case .bloom: return "Bass Echo"
        case .towers: return "Spectrum Towers"
        case .aurora: return "Aurora Curtains"
        case .meteor: return "Meteor Trails"
        case .ember: return "Ember Drift"
        case .cinema: return "Cinema Wash"
        }
    }

    var detail: String {
        switch self {
        case .ensemble: return "Bass carries the rim, mids wash across the center, and treble colors the number row in slow phrases."
        case .orbits: return "Two pools of light circle in opposite directions. Bass widens the amber pool and treble stretches the cyan orbit."
        case .tempo: return "A continuous color wave timed to the beat of your music."
        case .percussion: return "Drums trace the edge, hi-hats light the number row, and four frequency bands fill the middle."
        case .bloom: return "Each bass hit launches a wave that keeps traveling as the next one starts."
        case .towers: return "Twelve equalizer columns climb the keyboard from bass to treble."
        case .aurora: return "Mint and violet ribbons fold across a dark sky."
        case .meteor: return "Staggered comets cross alternating rows, leaving warm amber tails."
        case .ember: return "Slow pockets of copper and gold rise through a deep red glow."
        case .cinema: return "Five pools of screen color blend across the board, with a warm bass accent along the bottom."
        }
    }

    func makeScene() -> LightingScene {
        let layers: [Layer]
        switch self {
        case .ensemble:
            var glide = Layer(effect: .ensemble, color: RGB(r: 1, g: 0.29, b: 0.31), secondary: RGB(r: 0.94, g: 0.63, b: 1))
            glide.middle = RGB(r: 0.24, g: 0.46, b: 0.94)
            layers = [glide]
        case .orbits:
            var orbit = Layer(effect: .orbits, color: RGB(r: 1, g: 0.58, b: 0.13), secondary: RGB(r: 0.12, g: 0.93, b: 1))
            orbit.middle = RGB(r: 0.22, g: 0.10, b: 0.53)
            layers = [orbit]
        case .tempo: layers = [Layer(effect: .tempo, color: RGB(r: 0.10, g: 0.19, b: 0.95), secondary: RGB(r: 1, g: 0.26, b: 0.55))]
        case .towers:
            var bars = Layer(effect: .towers, color: RGB(r: 0.04, g: 0.92, b: 0.70), secondary: RGB(r: 1, g: 0.51, b: 0.08))
            bars.audio.smoothing = 0.065
            layers = [Layer(effect: .solid, color: RGB(r: 0.015, g: 0.035, b: 0.05)), bars]
        case .bloom:
            let bed = Layer(effect: .solid, color: RGB(r: 0.035, g: 0.025, b: 0.095))
            let echo = Layer(effect: .bloom, color: RGB(r: 1, g: 0.32, b: 0.44), secondary: RGB(r: 0.35, g: 0.44, b: 1),
                             response: AudioResponse(gain: 1.25, fade: 0.8))
            layers = [bed, echo]
        case .aurora: layers = [Layer(effect: .aurora, color: RGB(r: 0.15, g: 1, b: 0.67), secondary: RGB(r: 0.49, g: 0.19, b: 1), speed: 0.36)]
        case .meteor: layers = [Layer(effect: .meteors, color: RGB(r: 1, g: 0.92, b: 0.72), secondary: RGB(r: 1, g: 0.25, b: 0.04), speed: 0.60)]
        case .ember: layers = [Layer(effect: .embers, color: RGB(r: 0.48, g: 0.035, b: 0.012), secondary: RGB(r: 1, g: 0.63, b: 0.11), speed: 0.48)]
        case .cinema:
            let bottom = Set(Board.keys.filter { $0.y == 5.25 }.map(\.id))
            layers = [Layer(effect: .cinema), Layer(effect: .bass, color: RGB(r: 1, g: 0.63, b: 0.38), opacity: 0.45, keys: bottom)]
        case .percussion: return .drumScene
        }
        return LightingScene(id: id, name: title, layers: layers, brightness: 0.82)
    }
}

extension LightingScene {
    var factoryMode: FactoryMode? { FactoryMode(rawValue: id.uuidString) }
    var inputLabel: String {
        let screen = layers.contains { $0.effect.usesScreen }
        let audio = layers.contains { $0.respondsToAudio || $0.usesSilenceColor }
        if screen && audio { return "Screen + audio" }
        if screen { return "Screen" }
        return audio ? "Music" : "Ambient"
    }

    // The first two releases generated random IDs for these starters. Only
    // retire exact stock configurations. A renamed or edited scene is personal.
    var legacyReplacement: FactoryMode? {
        guard brightness == 0.7, factoryMode == nil else { return nil }
        let stock: [Layer]
        let destination: FactoryMode
        switch name {
        case "Northern lights": stock = [Layer()]; destination = .aurora
        case "Screen + bass": stock = [Layer(effect: .screen), Layer(effect: .bass, keys: [75])]; destination = .cinema
        default: return nil
        }
        guard layers.count == stock.count else { return nil }
        for (actual, var expected) in zip(layers, stock) {
            expected.id = actual.id
            if actual != expected { return nil }
        }
        return destination
    }
}

extension Library {
    static func initial() -> Library {
        Library(scenes: FactoryMode.allCases.map { $0.makeScene() }, selected: FactoryMode.tempo.id)
    }

    mutating func updateCatalog() {
        let kept = scenes.filter { $0.legacyReplacement == nil }
        if let old = scenes.first(where: { $0.id == selected }), let replacement = old.legacyReplacement {
            selected = replacement.id
        }
        scenes = FactoryMode.allCases.map { mode in
            guard var existing = kept.first(where: { $0.id == mode.id }) else { return mode.makeScene() }
            if mode == .percussion {
                existing.upgradeDrumPreset()
                if existing.name == "Drum perimeter" { existing.name = mode.title }
            }
            return existing
        } + kept.filter { $0.factoryMode == nil }
    }
}

extension FactoryMode {
    // Illustrative snapshots for the mode browser. Only the live capture path
    // supplies audio and display values to the keyboard.
    static let thumbnails: [FactoryMode: [RGB]] = Dictionary(uniqueKeysWithValues: allCases.map { mode in
        let scene = mode.makeScene()
        var signals = Signals()
        signals.screen = Board.keys.map { key in
            let p = (key.x + key.width / 2) / Board.width
            let dusk = RGB(r: 0.92, g: 0.30, b: 0.12)
            return dusk.mix(RGB(r: 0.11, g: 0.18, b: 0.91), p)
        }
        for layer in scene.layers where layer.respondsToAudio {
            signals.audio[layer.id] = AudioReading(levels: layer.effect == .towers
                ? [0.63, 0.88, 0.72, 0.40, 0.31, 0.53, 0.76, 0.95, 0.61, 0.48, 0.34, 0.54] : [0.48, 0.91, 0.36, 0.68], strength: 0.95, age: mode == .bloom ? 0.27 : 0.018,
                                                  echoHits: layer.effect == .bloom ? [EchoHit(onset: 0, strength: 0.95)] : [])
        }
        return (mode, EffectEngine.render(scene, time: 2.6, signals: signals))
    })
}
