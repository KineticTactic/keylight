import XCTest
@testable import Keylight

final class SilenceTests: XCTestCase {
    func testSilenceFadeWaitsReturnsSmoothlyAndClearsOnCaptureStop() {
        var fade = SilenceFade()
        XCTAssertEqual(fade.update(quietDuration: 1.49, delta: 0.033), 0)
        XCTAssertEqual(fade.update(quietDuration: 2.4, delta: 0.033), 0.5, accuracy: 0.0001)
        XCTAssertEqual(fade.update(quietDuration: 3.31, delta: 0.033), 1)
        let returning = fade.update(quietDuration: 0, delta: 0.033)
        XCTAssertGreaterThan(returning, 0)
        XCTAssertLessThan(fade.update(quietDuration: 0, delta: 0.067), 0.05)
        XCTAssertEqual(fade.update(quietDuration: nil, delta: 0.033), 0)
    }

    func testSilenceColorCompositesEveryEffectUsingMaskAndOpacity() {
        let red = RGB(r: 1, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 1)
        for effect in Effect.allCases {
            var layer = Layer(effect: effect, opacity: 0.5, keys: [75])
            layer.silenceColor = blue
            let scene = LightingScene(layers: [Layer(effect: .solid, color: red), layer], brightness: 1)
            let frame = EffectEngine.render(scene, time: 0, signals: Signals(silenceBlend: 1))
            XCTAssertEqual(frame[75], red.mix(blue, 0.5))
            XCTAssertEqual(frame[0], red)
            layer.usesSilenceColor = false
            XCTAssertEqual(layer.silenceColor, blue)
            XCTAssertFalse(layer.usesSilenceColor)
        }
    }

    func testInputGainScalesMeterLayerAndBroadbandSilenceTogether() {
        let analyzer = AudioSpectrum()
        var layer = Layer(effect: .bass)
        layer.frequencyBands[0].thresholdDB = -57
        analyzer.configure([AudioRoute(layer)])
        let samples = (0..<8192).map { Float(0.00045 * sin(2 * .pi * 93.75 * Double($0) / 48_000)) }
        analyzer.ingest(samples, rate: 48_000)
        let quietPeak = analyzer.meter.max()!
        XCTAssertGreaterThan(analyzer.quietDuration, 0.15)
        XCTAssertEqual(analyzer.readings[layer.id]?.levels[0], 0)
        analyzer.inputGainDB = 20
        analyzer.ingest(samples, rate: 48_000)
        XCTAssertEqual(analyzer.meter.max()!, quietPeak * 10, accuracy: 0.00001)
        XCTAssertGreaterThan(analyzer.readings[layer.id]!.levels[0], 0.005)
        XCTAssertEqual(analyzer.quietDuration, 0)
        analyzer.ingest(.init(repeating: 0, count: 96_000), rate: 48_000)
        XCTAssertGreaterThan(analyzer.quietDuration, 1.9)
    }

    @MainActor func testLegacyLibraryAndNewSettingsSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Scenes.json")
        try JSONEncoder().encode(Library.initial()).write(to: url)
        let old = Studio(file: url)
        XCTAssertEqual(old.inputGainDB, 0)
        old.selected = FactoryMode.ensemble.id
        old.inputGainDB = 12
        old.scene.layers[0].reactivity = 1.6
        old.scene.layers[0].usesSilenceColor = true
        old.scene.layers[0].silenceColor = RGB(r: 0.4, g: 0.3, b: 0.2)
        old.finish()
        let loaded = Studio(file: url)
        XCTAssertEqual(loaded.inputGainDB, 12)
        XCTAssertEqual(loaded.scene, old.scene)
        loaded.finish()
    }
}
