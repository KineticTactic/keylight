import XCTest
@testable import Keylight

final class TowerTests: XCTestCase {
    func testEveryBandHasItsOwnDetectorAndPhysicalColumn() throws {
        let scene = FactoryMode.towers.makeScene()
        let layer = try XCTUnwrap(scene.layers.first { $0.effect == .towers })
        let silence = EffectEngine.render(scene, time: 0, signals: Signals())
        XCTAssertEqual(layer.frequencyBands.count, 12)
        for (index, band) in layer.frequencyBands.enumerated() {
            let analyzer = AudioSpectrum()
            analyzer.configure([AudioRoute(layer)])
            let hz = sqrt(band.low * band.high)
            let samples = (0..<6144).map { Float(0.15 * sin(2 * .pi * hz * Double($0) / 48000)) }
            analyzer.ingest(samples, rate: 48000)
            let levels = try XCTUnwrap(analyzer.readings[layer.id]?.levels)
            XCTAssertEqual(levels.count, 12)
            XCTAssertEqual(levels.firstIndex(of: try XCTUnwrap(levels.max())), index, "Tone at \(hz) Hz")

            var isolated = Array(repeating: 0.0, count: 12)
            isolated[index] = 1
            let signals = Signals(audio: [layer.id: AudioReading(levels: isolated)])
            let frame = EffectEngine.render(scene, time: 0, signals: signals)
            let changed = Set(Board.keys.filter { frame[$0.id] != silence[$0.id] }.map(\.id))
            let column = Set(Board.keys.filter { Int(($0.x + $0.width / 2) * 12 / Board.width) == index }.map(\.id))
            XCTAssertFalse(column.isEmpty)
            XCTAssertEqual(changed, column)
        }
    }

    func testLegacyTuningAndCaptureTransitions() throws {
        var scene = FactoryMode.towers.makeScene()
        var layer = scene.layers[1]
        let previous = [
            FrequencyBand(low: 62, high: 410, thresholdDB: -47, gain: 2.25),
            FrequencyBand(low: 600, high: 601, thresholdDB: -35, gain: 0.75),
            FrequencyBand(low: 900, high: 3600, thresholdDB: -44, gain: 1.7),
            FrequencyBand(low: 3600, high: 18500, thresholdDB: -52, gain: 3)
        ]
        layer.tuning = [Effect.towers.rawValue: previous]
        let restored = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer))
        for (i, old) in previous.enumerated() {
            let three = restored.frequencyBands[(i * 3)..<(i * 3 + 3)]
            XCTAssertEqual(three.first?.low, old.low)
            XCTAssertEqual(three.last?.high, old.high)
            XCTAssertTrue(three.allSatisfy { $0.gain == old.gain && $0.thresholdDB == old.thresholdDB && $0.high - $0.low >= 1 })
        }
        layer.frequencyBands[11].gain = 0.23
        XCTAssertEqual(layer.frequencyBands[10].gain, 3)
        XCTAssertEqual(try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer)).frequencyBands[11].gain, 0.23)
        scene.layers[1] = layer
        var filter = BandSmoothing()
        _ = filter.update(scene: scene, audio: [:], delta: 1)
        var levels = Array(repeating: 0.0, count: 12)
        levels[11] = 1
        let smoothed = filter.update(scene: scene, audio: [layer.id: AudioReading(levels: levels)], delta: 1)
        XCTAssertGreaterThan(try XCTUnwrap(smoothed[layer.id]?.last), 0.9)
        XCTAssertEqual(FrequencyBand.defaults(for: .spectrum).count, 4)
    }
}
