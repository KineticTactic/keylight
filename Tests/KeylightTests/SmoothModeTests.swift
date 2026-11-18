import XCTest
@testable import Keylight

final class SmoothModeTests: XCTestCase {
    func testPlaybackTempoAndMixDriveBothModes() throws {
        let layers = [FactoryMode.ensemble, .orbits].map { $0.makeScene().layers[0] }
        let analyzer = AudioSpectrum()
        analyzer.configure(layers.map(AudioRoute.init))
        let rate = 48_000.0
        var beat = [Float](repeating: 0, count: 24_000)
        for i in 0..<3200 {
            let t = Double(i) / rate
            beat[i] = Float(0.6 * sin(2 * .pi * 90 * t) * exp(-t * 45))
        }
        for _ in 0..<10 { analyzer.ingest(beat, rate: rate) }
        for layer in layers {
            XCTAssertEqual(try XCTUnwrap(analyzer.readings[layer.id]?.bpm), 120, accuracy: 3)
        }
        for (band, hz) in [93.75, 750, 6000].enumerated() {
            let tone = (0..<4096).map { Float(0.4 * sin(2 * .pi * hz * Double($0) / rate)) }
            analyzer.ingest(tone, rate: rate)
            for layer in layers {
                let reading = try XCTUnwrap(analyzer.readings[layer.id])
                XCTAssertGreaterThan(reading.levels[band], 0.8)
            }
        }
    }

    func testMusicChangesGlideAndMotionContinuesThroughSilence() {
        for mode in [FactoryMode.ensemble, .orbits] {
            let scene = mode.makeScene()
            let layer = scene.layers[0]
            var filter = BandSmoothing()
            var signals = Signals()
            let frameTime = 1.0 / 30
            func frame(at beats: Double, mix: [Double]) -> [RGB] {
                signals.audio[layer.id] = AudioReading(levels: mix)
                signals.rhythmBeats[layer.id] = beats
                let levels = filter.update(scene: scene, audio: signals.audio, delta: frameTime)
                return EffectEngine.render(scene, time: 0, signals: signals, smoothedBands: levels)
            }
            let silent = [0.0, 0, 0, 0]
            let start = frame(at: 0, mix: silent)
            XCTAssertNotEqual(start, frame(at: 4, mix: silent))
            let peak = [1.0, 0, 0, 0]
            let immediate = frame(at: 0, mix: peak)
            var sustained = immediate
            for _ in 0..<120 { sustained = frame(at: 0, mix: peak) }
            func largestChange(from original: [RGB], to changed: [RGB]) -> Double {
                zip(original, changed).map { a, b in
                    max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
                }.max() ?? 0
            }
            XCTAssertLessThan(largestChange(from: start, to: immediate), 0.025)
            XCTAssertGreaterThan(largestChange(from: start, to: sustained), 0.10)
            if mode == .ensemble {
                XCTAssertGreaterThan(sustained[0].r, start[0].r)
                XCTAssertEqual(sustained[15], start[15]) // bass leaves digit colors independent
                XCTAssertEqual(sustained[50], start[50])
            }
        }
    }
}
