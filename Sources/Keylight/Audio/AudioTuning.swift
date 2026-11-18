import Foundation

struct FrequencyBand: Codable, Equatable {
    static let domain = 30.0...20000.0
    var low: Double
    var high: Double
    var thresholdDB: Double
    var gain = 1.0

    var threshold: Double { pow(10, thresholdDB / 20) }

    static let towerBands: [FrequencyBand] = {
        let edges = [45.0, 105, 215, 450, 625, 865, 1200, 1665, 2310, 3200, 5470, 9360, 16000]
        return zip(edges, edges.dropFirst()).map { .init(low: $0, high: $1, thresholdDB: -80) }
    }()

    // Expand each saved zone in place, including its personal gain and threshold.
    func subdividedForTowers() -> [FrequencyBand] {
        guard high - low >= 3 else { return Array(repeating: self, count: 3) }
        let first = min(high - 2, max(low + 1, low * pow(high / low, 1.0 / 3)))
        let second = min(high - 1, max(first + 1, low * pow(high / low, 2.0 / 3)))
        let edges = [low, first, second, high]
        return zip(edges, edges.dropFirst()).map { .init(low: $0, high: $1, thresholdDB: thresholdDB, gain: gain) }
    }

    static func defaults(for effect: Effect) -> [FrequencyBand] {
        switch effect {
        case .bloom: return [.init(low: 30, high: 220, thresholdDB: -38)]
        case .drum, .tempo, .ensemble, .orbits: return [.init(low: 30, high: 16000, thresholdDB: 20 * log10(0.014))]
        case .hiHat: return [.init(low: 5500, high: 16000, thresholdDB: 20 * log10(0.006))]
        case .towers: return towerBands
        case .spectrum:
            let edges = [180.0, 450, 1200, 3200, 16000]
            return zip(edges, edges.dropFirst()).map { .init(low: $0, high: $1, thresholdDB: -80) }
        case .bass: return [.init(low: 30, high: 150, thresholdDB: -80)]
        default: return [.init(low: 30, high: 16000, thresholdDB: -55)]
        }
    }
}

extension Layer {
    var respondsToAudio: Bool { effect.usesAudio || audioModulation == true }
    var frequencyBands: [FrequencyBand] {
        get {
            let defaults = FrequencyBand.defaults(for: effect)
            guard let saved = tuning?[effect.rawValue],
                  saved.allSatisfy({ FrequencyBand.domain.contains($0.low) && FrequencyBand.domain.contains($0.high) && $0.high - $0.low >= 1 })
            else { return defaults }
            if effect == .towers && saved.count == 4 { return saved.flatMap { $0.subdividedForTowers() } }
            return saved.count == defaults.count ? saved : defaults
        }
        set {
            if tuning == nil { tuning = [:] }
            tuning?[effect.rawValue] = newValue
        }
    }
}

struct AudioRoute: Equatable {
    let id: UUID
    let effect: Effect
    let bands: [FrequencyBand]
    let echoLifetime: Double
    let triggerGain: Double

    init(_ layer: Layer) {
        id = layer.id
        effect = layer.effect
        bands = layer.frequencyBands
        echoLifetime = layer.effect == .bloom ? max(0.06, layer.audio.fade) : 0
        triggerGain = layer.effect.followsTempo ? layer.audio.gain : 1
    }
}

struct AudioReading {
    var levels = [Double](repeating: 0, count: 4)
    var strength = 0.0
    var age = Double.infinity
    var bpm: Double?
    var tempoEvidenceAge = Double.infinity
    var echoHits: [EchoHit] = []
}

struct SpectrumMeter {
    static let count = 48
    static let edges = (0...count).map { index in
        30 * pow(20000 / 30.0, Double(index) / Double(count))
    }
    static let silent = Array(repeating: 0.0, count: count)
}

// A cumulative sum gives every detector and display bar access to the same FFT.
// Fractional edge bins avoid dropping a narrow bass range between two bin centers.
struct FFTPower {
    var sum: [Double]
    var binHz: Double
    var scale: Double

    func amplitude(_ low: Double, _ high: Double) -> Double {
        func cumulative(_ hz: Double) -> Double {
            let edge = min(Double(sum.count - 1), max(0, hz / binHz + 0.5))
            let i = Int(edge)
            guard i + 1 < sum.count else { return sum[i] }
            return sum[i] + (edge - Double(i)) * (sum[i + 1] - sum[i])
        }
        return sqrt(max(0, cumulative(high) - cumulative(low))) * scale
    }
}

struct LayerDetector {
    var route: AudioRoute
    var reading = AudioReading()
    private var tracker = TempoTracker()
    private var regionalAverage = [Double](repeating: 0, count: 3)
    private var fluxFloor = 0.0
    private var sampleTime = 0.0
    private var previous = Array(repeating: 0.0, count: 5)
    private var average = Array(repeating: 0.0, count: 5)

    init(_ route: AudioRoute) {
        self.route = route
        if route.effect == .towers { reading.levels = Array(repeating: 0, count: route.bands.count) }
    }

    mutating func analyze(_ fft: FFTPower, delta: Double) {
        reading.age += delta
        sampleTime += delta
        let band = route.bands[0]
        switch route.effect {
        case .hiHat, .drum, .tempo, .bloom, .ensemble, .orbits:
            if route.effect.usesMix {
                // Share of energy in the lows, mids and highs. A small floor
                // lets the color balance relax when playback goes quiet.
                let low = fft.amplitude(35, 200)
                let mid = fft.amplitude(200, 2500)
                let high = fft.amplitude(2500, 16000)
                let total = 0.02 + low + mid + high
                if route.effect == .ensemble {
                    // Mix share alone barely moves in a mastered track. Follow
                    // each region's own loudness too, and carry short notes
                    // across the gap between FFT and display frames.
                    let tail = exp(-delta / 0.14)
                    let adapt = 1 - exp(-delta / 1.4)
                    for (i, amplitude) in [low, mid, high].enumerated() {
                        let presence = amplitude / (amplitude + 0.045)
                        let baseline = regionalAverage[i]
                        let lift = min(1, max(0, (amplitude - 1.10 * baseline) / (0.012 + baseline)))
                        regionalAverage[i] += (amplitude - baseline) * adapt
                        let target = min(1, 0.26 * amplitude / total + 0.50 * presence + 0.62 * lift)
                        reading.levels[i] = max(target, reading.levels[i] * tail)
                    }
                } else {
                    reading.levels = [low / total, mid / total, high / total, 0]
                }
            }
            let isHat = route.effect == .hiHat
            let original = isHat ? [5500.0, 9000, 16000] : [30.0, 180, 450, 1200, 3200, 16000]
            let ratio = original.last! / original[0]
            let edges = original.map { band.low * pow(band.high / band.low, log($0 / original[0]) / log(ratio)) }
            let amplitudes = zip(edges, edges.dropFirst()).map { fft.amplitude($0, $1) }
            let energies: [Double]
            if route.effect == .bloom { energies = [fft.amplitude(band.low, band.high)] }
            else if isHat { energies = [min(amplitudes[0], amplitudes[1])] }
            else { energies = amplitudes }
            let blend = 1 - exp(-delta / (isHat ? 0.12 : 0.18))
            let tempo = route.effect.followsTempo
            let rises = energies.indices.map { i in
                let rise = max(0, energies[i] - max(previous[i] * (isHat ? 1.15 : 1.12), average[i] * (isHat ? 1.5 : 1.45)))
                // Normalize tempo attacks to their local band level so a quiet
                // snare or a kick over sustained bass can register independently.
                let flux = max(0, energies[i] - max(previous[i] * 1.025, average[i] * 0.85))
                    / (0.14 + sqrt(average[i]))
                previous[i] = energies[i]
                average[i] += (energies[i] - average[i]) * blend
                return tempo ? flux : rise
            }
            var attack = energies.count == 1 ? rises[0] : max(rises[0], min(rises[1] + rises[2], rises[3] + rises[4]) * 1.7)
            var threshold = band.threshold
            if tempo {
                attack = max(rises[0], 0.85 * max(rises[1], rises[2]), 0.65 * max(rises[3], rises[4]))
                threshold += fluxFloor * 1.35
                fluxFloor += (attack - fluxFloor) * (1 - exp(-delta / 0.32))
            }
            let minimumGap = isHat || route.effect == .bloom ? 0.042 : 0.085
            if attack * route.triggerGain > threshold, reading.age >= minimumGap {
                reading.strength = min(1, sqrt(attack * (isHat ? 12 : 5)))
                reading.age = 0
                if route.effect == .bloom {
                    reading.echoHits.removeAll { sampleTime - $0.onset >= route.echoLifetime }
                    reading.echoHits.append(EchoHit(onset: sampleTime, strength: reading.strength))
                }
                if route.effect.followsTempo { tracker.hit(at: sampleTime, strength: sqrt(attack)) }
            }
            if tempo {
                reading.tempoEvidenceAge = sampleTime - tracker.confirmedAt
                reading.bpm = reading.tempoEvidenceAge < TempoTracker.expiry ? tracker.bpm : nil
            }
        default:
            for (i, band) in route.bands.enumerated() {
                let amplitude = fft.amplitude(band.low, band.high)
                let level = amplitude >= band.threshold ? amplitude * 3.5 * band.gain : 0
                reading.levels[i] = max(min(1, level), reading.levels[i] * exp(-delta / 0.10))
            }
        }
    }
}
