import XCTest
@testable import Keylight

final class MusicTests: XCTestCase {
    private let rate = 48_000.0
    private func tone(_ hz: Double, count: Int, amplitude: Double = 0.24) -> [Float] {
        (0..<count).map { Float(amplitude * sin(Double($0) * hz * 2 * .pi / rate)) }
    }

    func testRoutingFromAudioThroughPreset() {
        let scene = LightingScene.drumScene
        let spectrum = AudioSpectrum()
        spectrum.configure(scene.layers.map(AudioRoute.init))
        spectrum.ingest(tone(70, count: 1024), rate: rate)
        func render() -> [RGB] {
            EffectEngine.render(scene, time: 0, signals: Signals(audio: spectrum.readings))
        }
        let kick = render()
        XCTAssertGreaterThan(kick[0].r, 0.4)
        for key in Board.perimeter {
            XCTAssertEqual(kick[key], kick[0])
            XCTAssertEqual(kick[key].g + kick[key].b, 0)
        }
        let sustained = tone(2000, count: 48000)
        // Fragmentation matches capture callbacks whose sizes differ from the FFT window.
        for start in stride(from: 0, to: sustained.count, by: 360) {
            spectrum.ingest(Array(sustained[start..<min(start + 360, sustained.count)]), rate: rate)
        }
        let mids = render()
        XCTAssertEqual(mids[75], .black)
        XCTAssertGreaterThan(mids[39].b, 0.1) // P lies in the third band.
        XCTAssertLessThan(mids[30].g, 0.01)
        XCTAssertEqual(Board.perimeter.union(Board.interior), Set(Board.keys.map(\.id)))
        XCTAssertTrue(Board.perimeter.isDisjoint(with: Board.interior))
    }

    func testSustainedBassDoesNotKeepTriggeringAndNextKickRetriggers() {
        let audio = AudioSpectrum()
        let drum = Layer(effect: .drum)
        audio.configure([AudioRoute(drum)])
        audio.ingest(tone(70, count: 48000), rate: rate)
        XCTAssertGreaterThan(audio.readings[drum.id]!.age, 0.7)
        audio.ingest([Float](repeating: 0, count: 8192), rate: rate)
        audio.ingest(tone(70, count: 2048), rate: rate)
        XCTAssertLessThan(audio.readings[drum.id]!.age, 0.06)
        XCTAssertGreaterThan(audio.readings[drum.id]!.strength, 0.4)
    }

    func testBroadSnareAttackAndFourSeparateBands() {
        let audio = AudioSpectrum()
        let drum = Layer(effect: .drum)
        audio.configure([AudioRoute(drum)])
        let body = tone(700, count: 1024), crack = tone(4500, count: 1024)
        audio.ingest(zip(body, crack).map(+), rate: rate)
        XCTAssertGreaterThan(audio.readings[drum.id]!.strength, 0.5)
        for (band, hz) in [310.0, 740, 1950, 6400].enumerated() {
            let analysis = AudioSpectrum()
            let layer = Layer(effect: .spectrum)
            analysis.configure([AudioRoute(layer)])
            analysis.ingest(tone(hz, count: 4096), rate: rate)
            let levels = analysis.readings[layer.id]!.levels
            XCTAssertEqual(levels.firstIndex(of: levels.max()!), band)
            XCTAssertGreaterThan(levels[band], 0.4)
        }
    }

    func testDrumGainAndFade() {
        var scene = LightingScene.drumScene
        scene.brightness = 1
        let hit = Signals(audio: [scene.layers[1].id: AudioReading(strength: 0.4, age: 0.1)])
        scene.layers[1].audio.fade = 0.05
        XCTAssertEqual(EffectEngine.render(scene, time: 0, signals: hit)[0], .black)
        scene.layers[1].audio.fade = 0.5
        let first = EffectEngine.render(scene, time: 0, signals: hit)[0].r
        scene.layers[1].audio.gain = 2
        XCTAssertEqual(EffectEngine.render(scene, time: 0, signals: hit)[0].r, first * 2, accuracy: 0.001)
    }

    @MainActor func testExistingLibraryGetsOnePresetAndKeepsSelection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Scenes.json")
        let original = LightingScene(name: "My setup", layers: [Layer(effect: .bass, keys: [75])])
        try JSONEncoder().encode(Library(scenes: [original], selected: original.id)).write(to: url)
        let studio = Studio(file: url)
        XCTAssertEqual(studio.scene, original)
        XCTAssertEqual(studio.scene.layers[0].audio.gain, 1)
        studio.selected = LightingScene.drumSceneID
        XCTAssertTrue(studio.usesCapture)
        studio.scene.layers[1].audio.fade = 0.63
        studio.finish()
        let reloaded = Studio(file: url)
        XCTAssertEqual(reloaded.scenes.count, FactoryMode.allCases.count + 1)
        XCTAssertEqual(reloaded.scene.layers[1].audio.fade, 0.63)
        reloaded.finish()
    }
}
