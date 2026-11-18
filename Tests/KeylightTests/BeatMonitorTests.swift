import XCTest
@testable import Keylight

final class BeatMonitorTests: XCTestCase {
    func testQuietMidrangeBeatSurvivesFillsAndSkippedNotes() throws {
        let rate = 48_000.0
        let layer = FactoryMode.tempo.makeScene().layers[0]
        let analyzer = AudioSpectrum()
        analyzer.configure([AudioRoute(layer)])
        // 110 BPM, a sustained pad, quiet pitched attacks and irregular hats.
        let interval = Int((rate * 60 / 110).rounded())
        var locked = 0
        for beat in 0..<24 {
            var samples = [Float](repeating: 0, count: interval)
            let fill = [0.28, 0.57, 0.72, 0.44][beat % 4]
            for i in samples.indices {
                let t = Double(i) / rate
                let global = Double(beat * interval + i) / rate
                let hat = t - fill * Double(interval) / rate
                var value = 0.035 * sin(2 * .pi * 187.5 * global)
                if beat % 7 != 4 { value += 0.019 * sin(2 * .pi * 750 * t) * exp(-t * 38) }
                if hat >= 0 { value += 0.008 * sin(2 * .pi * 6000 * hat) * exp(-hat * 85) }
                samples[i] = Float(value)
            }
            analyzer.ingest(samples, rate: rate)
            if beat >= 7, abs((analyzer.readings[layer.id]?.activeTempo ?? 0) - 110) < 4 { locked += 1 }
        }
        XCTAssertGreaterThanOrEqual(locked, 15) // at least 15 of the last 17 beats
        analyzer.ingest(.init(repeating: 0, count: 144_000), rate: rate)
        XCTAssertNil(analyzer.readings[layer.id]?.activeTempo)
    }

    func testDetectionAndClockUseIndependentSignals() {
        var motion = RhythmMotion()
        _ = motion.advance(by: 0.12, bpm: nil, onsetAge: .infinity)
        let input = AudioReading(age: 0.02, bpm: 120, tempoEvidenceAge: 0)
        let live = BeatMonitor(reading: input, motion: motion)
        XCTAssertGreaterThan(live.hitLight, 0.8)
        XCTAssertEqual(live.detectedBPM, 120)
        XCTAssertEqual(live.clockBPM, 75)
        XCTAssertEqual(live.phase, motion.beats, accuracy: 0.0001)
        var old = input
        old.age = 1.4
        old.tempoEvidenceAge = 1.4
        XCTAssertTrue(BeatMonitor(reading: old, motion: motion).holding)
        old.tempoEvidenceAge = 3
        let expired = BeatMonitor(reading: old, motion: motion)
        XCTAssertNil(expired.detectedBPM)
        XCTAssertEqual(expired.hitLight, 0)
        _ = motion.advance(by: 0.1, bpm: nil, onsetAge: .infinity)
        XCTAssertNotEqual(BeatMonitor(reading: nil, motion: motion).phase, expired.phase)
    }

    func testVelvetBandEnergyReachesTheIntendedKeysWithoutTempoLock() {
        let scene = FactoryMode.ensemble.makeScene()
        let layer = scene.layers[0]
        let analyzer = AudioSpectrum()
        analyzer.configure([AudioRoute(layer)])
        var filter = BandSmoothing()
        func render(_ frequencies: [Double], volume: Double) -> [RGB] {
            let frameCount = 1600
            var result = [RGB]()
            for frame in 0..<60 {
                let pcm = (0..<frameCount).map { i -> Float in
                    let t = Double(frame * frameCount + i) / 48_000
                    return Float(frequencies.reduce(0.0) { $0 + volume * sin(2 * .pi * $1 * t) })
                }
                analyzer.ingest(pcm, rate: 48_000)
                let readings = analyzer.readings
                let bands = filter.update(scene: scene, audio: readings, delta: 1.0 / 30)
                result = EffectEngine.render(scene, time: 0, signals: Signals(audio: readings), smoothedBands: bands)
            }
            return result
        }
        let bass = render([93.75], volume: 0.12)
        let treble = render([6000], volume: 0.12)
        XCTAssertGreaterThan(bass[0].r - treble[0].r, 0.20)
        XCTAssertGreaterThan(treble[15].b - bass[15].b, 0.20)
        let quiet = render([93.75, 750, 6000], volume: 0.006)
        let loud = render([93.75, 750, 6000], volume: 0.18)
        for id in [0, 15, 50] {
            let a = quiet[id], b = loud[id]
            XCTAssertGreaterThan(max(b.r - a.r, b.g - a.g, b.b - a.b), 0.12)
        }
    }
    func testVelvetShowsShortAccentsOverAnAlreadyPlayingMix() {
        let scene = FactoryMode.ensemble.makeScene()
        let layer = scene.layers[0]
        let analyzer = AudioSpectrum()
        analyzer.configure([AudioRoute(layer)])
        var filter = BandSmoothing()
        var time = 0
        func frame(accent: Int?) -> [RGB] {
            let frequencies = [93.75, 750, 6000.0]
            let pcm = (0..<1600).map { index -> Float in
                let t = Double(time + index) / 48_000
                return Float(frequencies.enumerated().reduce(0.0) { sum, band in
                    sum + (band.offset == accent ? 0.18 : 0.025) * sin(2 * .pi * band.element * t)
                })
            }
            time += pcm.count
            analyzer.ingest(pcm, rate: 48_000)
            let audio = analyzer.readings
            let levels = filter.update(scene: scene, audio: audio, delta: 1.0 / 30)
            return EffectEngine.render(scene, time: 0, signals: Signals(audio: audio), smoothedBands: levels)
        }
        for (band, key) in [0, 50, 15].enumerated() {
            var baseline = RGB.black
            for _ in 0..<120 { baseline = frame(accent: nil)[key] }
            var peak = 0.0
            for n in 0..<10 {
                let color = frame(accent: n < 4 ? band : nil)[key]
                peak = max(peak, abs(color.r - baseline.r), abs(color.g - baseline.g), abs(color.b - baseline.b))
            }
            XCTAssertGreaterThan(peak, 0.14, "A short accent should visibly move region \(band)")
        }
    }

}
