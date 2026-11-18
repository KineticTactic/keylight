import XCTest
@testable import Keylight

final class TuningTests: XCTestCase {
    private func samples(_ hz: Double, amplitude: Double = 0.15) -> [Float] {
        (0..<4096).map { Float(amplitude * sin(2 * .pi * hz * Double($0) / 48000)) }
    }

    func testSpectrumReadsPlaybackIndependentlyOfLighting() {
        let analyzer = AudioSpectrum()
        analyzer.ingest(samples(1000), rate: 48000)
        let peak = analyzer.meter.firstIndex(of: analyzer.meter.max()!)!
        XCTAssertLessThan(SpectrumMeter.edges[peak], 1050)
        XCTAssertGreaterThan(SpectrumMeter.edges[peak + 1], 950)
        XCTAssertGreaterThan(analyzer.meter[peak], 0.08)
        analyzer.ingest(.init(repeating: 0, count: 48000), rate: 48000)
        XCTAssertLessThan(analyzer.meter.max()!, 0.001)
    }

    func testIndependentZoneFrequenciesThresholdsAndGain() {
        var layer = Layer(effect: .spectrum)
        layer.frequencyBands = [
            .init(low: 800, high: 1500, thresholdDB: -50, gain: 1),
            .init(low: 800, high: 1500, thresholdDB: -50, gain: 2),
            .init(low: 800, high: 1500, thresholdDB: -5),
            .init(low: 5000, high: 8000, thresholdDB: -50)
        ]
        let analyzer = AudioSpectrum()
        analyzer.configure([AudioRoute(layer)])
        analyzer.ingest(samples(1000, amplitude: 0.05), rate: 48000)
        let zones = analyzer.readings[layer.id]!.levels
        XCTAssertGreaterThan(zones[0], 0.1)
        XCTAssertEqual(zones[1], zones[0] * 2, accuracy: 0.0001)
        XCTAssertEqual(zones[2], 0)
        XCTAssertEqual(zones[3], 0)
    }

    func testIndependentHitThresholdsAndRetuning() {
        for effect in [Effect.drum, .hiHat] {
            var quiet = Layer(effect: effect)
            quiet.frequencyBands[0].thresholdDB = -60
            var loud = quiet
            loud.id = UUID()
            loud.frequencyBands[0].thresholdDB = -2
            let analyzer = AudioSpectrum()
            let hit = effect == .drum ? samples(90) : zip(samples(7000), samples(11200)).map(+)
            analyzer.configure([AudioRoute(quiet), AudioRoute(loud)])
            analyzer.ingest(hit, rate: 48000)
            XCTAssertGreaterThan(analyzer.readings[quiet.id]!.strength, 0)
            XCTAssertEqual(analyzer.readings[loud.id]!.strength, 0)
            quiet.frequencyBands[0] = .init(low: 1000, high: 2200, thresholdDB: -30)
            analyzer.configure([AudioRoute(quiet), AudioRoute(loud)])
            analyzer.ingest(hit, rate: 48000)
            XCTAssertEqual(analyzer.readings[quiet.id]!.strength, 0)
        }
    }

    func testOptInBrightnessModulationAndPersistence() throws {
        var visual = Layer(effect: .solid, color: RGB(r: 1, g: 0, b: 0))
        let analyzer = AudioSpectrum()
        let plain = LightingScene(layers: [visual], brightness: 1)
        XCTAssertEqual(EffectEngine.render(plain, time: 0, signals: Signals())[0].r, 1)
        visual.audioModulation = true
        visual.frequencyBands = [.init(low: 200, high: 800, thresholdDB: -48)]
        visual.audio.gain = 0.5
        let scene = LightingScene(layers: [visual], brightness: 1)
        analyzer.configure([AudioRoute(visual)])
        analyzer.ingest(samples(400), rate: 48000)
        let light = EffectEngine.render(scene, time: 0, signals: Signals(audio: analyzer.readings))[0].r
        XCTAssertGreaterThan(light, 0.1)
        XCTAssertLessThanOrEqual(light, 0.5)
        XCTAssertEqual(EffectEngine.render(scene, time: 0, signals: Signals())[0], .black)
        XCTAssertEqual(try JSONDecoder().decode(LightingScene.self, from: JSONEncoder().encode(scene)), scene)
    }
}
