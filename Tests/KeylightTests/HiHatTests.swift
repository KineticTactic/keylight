import XCTest
@testable import Keylight

final class HiHatTests: XCTestCase {
    private let rate = 48_000.0

    // Deterministic, short metallic burst spanning both high-frequency ranges.
    private func burst() -> [Float] {
        (0..<2048).map { i in
            let time = Double(i) / rate
            let partials = [6300.0, 7850, 10130, 12673].map { sin(2 * .pi * $0 * time) }
            return Float(0.16 * exp(-time / 0.018) * partials.reduce(0, +))
        }
    }

    func testHatRetriggersAndRoutesOnlyToDigits() throws {
        let analyzer = AudioSpectrum()
        let scene = LightingScene.drumScene
        let hat = try XCTUnwrap(scene.layers.first { $0.effect == .hiHat })
        XCTAssertEqual(Set(Board.keys.filter { hat.keys!.contains($0.id) }.map(\.label)), Set("1234567890".map(String.init)))
        analyzer.configure([AudioRoute(hat)])
        for _ in 0..<3 {
            analyzer.ingest(burst(), rate: rate)
            XCTAssertGreaterThan(analyzer.readings[hat.id]!.strength, 0.4)
            XCTAssertLessThan(analyzer.readings[hat.id]!.age, 0.05)
            let signal = Signals(audio: analyzer.readings)
            let frame = EffectEngine.render(scene, time: 0, signals: signal)
            for key in Board.keys {
                if Board.numberRow.contains(key.id) {
                    XCTAssertGreaterThan(frame[key.id].r, 0.1)
                    XCTAssertGreaterThan(frame[key.id].b, frame[key.id].g)
                } else { XCTAssertEqual(frame[key.id], .black) }
            }
            analyzer.ingest(Array(repeating: 0, count: 8192), rate: rate)
            XCTAssertGreaterThan(analyzer.readings[hat.id]!.age, hat.audio.fade)
        }
        for hz in [70.0, 700, 7400, 12000] {
            let separate = AudioSpectrum()
            separate.configure([AudioRoute(hat)])
            let note = (0..<8192).map { Float(0.3 * sin(2 * .pi * hz * Double($0) / rate)) }
            separate.ingest(note, rate: rate)
            XCTAssertEqual(separate.readings[hat.id]!.strength, 0)
        }
    }

    func testInteriorSmoothingDampsFlickerWithoutDelayingBeatLayers() throws {
        var scene = LightingScene.drumScene
        let layer = scene.layers[0]
        var filter = BandSmoothing()
        var levels: [UUID: [Double]] = [:]
        var last = 0.0
        for index in 0..<30 {
            let target = Array(repeating: index.isMultiple(of: 2) ? 1.0 : 0.0, count: 4)
            levels = filter.update(scene: scene, audio: [layer.id: AudioReading(levels: target)], delta: 1.0 / 30)
            let current = try XCTUnwrap(levels[layer.id]?.first)
            XCTAssertLessThan(abs(current - last), 0.16)
            last = current
        }
        let hit = Signals(audio: [scene.layers[1].id: AudioReading(strength: 1, age: 0), scene.layers[2].id: AudioReading(strength: 1, age: 0)])
        let frame = EffectEngine.render(scene, time: 0, signals: hit, smoothedBands: levels)
        XCTAssertEqual(frame[0].r, scene.brightness)
        XCTAssertEqual(frame[15].b, scene.brightness)
        XCTAssertGreaterThan(frame[30].g, 0)
        scene.layers[0].audio.smoothing = 0
        XCTAssertTrue(filter.update(scene: scene, audio: [:], delta: 0.03).isEmpty)
    }

    @MainActor func testExistingDrumPresetUpgradesOnceAndPreservesEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Scenes.json")
        let spectrum = Layer(effect: .spectrum, opacity: 0.53, response: AudioResponse(gain: 1.6), keys: Board.interior)
        let drum = Layer(effect: .drum, keys: [0, 13])
        let original = LightingScene(id: LightingScene.drumSceneID, name: "My drums", layers: [spectrum, drum], brightness: 0.48)
        try JSONEncoder().encode(Library(scenes: [original], selected: original.id)).write(to: url)
        let studio = Studio(file: url)
        XCTAssertEqual(studio.scene.name, original.name)
        XCTAssertEqual(studio.scene.layers[0].id, spectrum.id)
        XCTAssertEqual(studio.scene.layers[0].keys, Board.interior.subtracting(Board.numberRow))
        XCTAssertEqual(studio.scene.layers[0].audio.gain, 1.6)
        XCTAssertEqual(studio.scene.layers[0].audio.smoothing, 0.20)
        XCTAssertEqual(studio.scene.layers[0].opacity, 0.53)
        XCTAssertEqual(studio.scene.layers[1], drum)
        XCTAssertEqual(studio.scene.layers.last?.keys, Board.numberRow)
        studio.scene.layers.removeLast()
        studio.scene.layers[0].audio.smoothing = 0.42
        studio.finish()
        let reloaded = Studio(file: url)
        XCTAssertEqual(studio.scene, reloaded.scene)
        reloaded.finish()
    }
}
