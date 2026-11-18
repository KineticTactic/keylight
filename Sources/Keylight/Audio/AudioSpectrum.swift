import Accelerate
import Foundation

final class AudioSpectrum {
    static let size = 1024
    private let fft = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)!
    private let zeros = [Float](repeating: 0, count: size)
    private let window = (0..<size).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(size))) }
    private var pending = [Float]()
    private var real = [Float](repeating: 0, count: size)
    private var imag = [Float](repeating: 0, count: size)
    var inputGainDB = 0.0
    private(set) var quietDuration = 0.0
    private var isQuiet = true
    private var sampleRate = 0.0
    private var detectors: [UUID: LayerDetector] = [:]
    private(set) var meter = SpectrumMeter.silent

    var readings: [UUID: AudioReading] {
        detectors.mapValues {
            var reading = $0.reading
            if sampleRate > 0 {
                let elapsed = Double(pending.count) / sampleRate
                reading.age += elapsed
                reading.tempoEvidenceAge += elapsed
            }
            return reading
        }
    }

    func configure(_ routes: [AudioRoute]) {
        var next: [UUID: LayerDetector] = [:]
        for route in routes {
            if var existing = detectors[route.id], existing.route.effect == route.effect, existing.route.bands.count == route.bands.count,
               zip(existing.route.bands, route.bands).allSatisfy({ $0.low == $1.low && $0.high == $1.high }) {
                // Gain and threshold edits retain onset history while music is playing.
                existing.route = route
                next[route.id] = existing
            } else {
                next[route.id] = LayerDetector(route)
            }
        }
        detectors = next
    }

    deinit { vDSP_DFT_DestroySetup(fft) }

    func ingest(_ samples: [Float], rate: Double) {
        guard rate > 0 else { return }
        if sampleRate != rate {
            pending.removeAll()
            detectors = detectors.mapValues { LayerDetector($0.route) }
            quietDuration = 0
            isQuiet = true
            meter = SpectrumMeter.silent
            sampleRate = rate
        }
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + Self.size - pending.count)
            pending.append(contentsOf: samples[start..<end])
            start = end
            if pending.count == Self.size {
                analyze()
                pending.removeAll(keepingCapacity: true)
            }
        }
    }

    private func analyze() {
        let size = Self.size
        let dt = Double(size) / sampleRate
        vDSP_vmul(pending, 1, window, 1, &pending, 1, vDSP_Length(size))
        vDSP_DFT_Execute(fft, pending, zeros, &real, &imag)
        var sum = Array(repeating: 0.0, count: size / 2 + 1)
        for bin in 0..<(size / 2) {
            sum[bin + 1] = sum[bin] + Double(real[bin] * real[bin] + imag[bin] * imag[bin])
        }
        let power = FFTPower(sum: sum, binHz: sampleRate / Double(size), scale: pow(10, inputGainDB / 20) * 4 / Double(size))
        let broadband = power.amplitude(20, sampleRate / 2)
        if broadband > 0.0025 { isQuiet = false }
        if broadband < 0.0014 { isQuiet = true }
        quietDuration = isQuiet ? quietDuration + dt : 0
        for i in meter.indices {
            let level = power.amplitude(SpectrumMeter.edges[i], SpectrumMeter.edges[i + 1])
            meter[i] = max(level, meter[i] * exp(-dt / 0.12))
        }
        for id in detectors.keys { detectors[id]?.analyze(power, delta: dt) }
    }
}
