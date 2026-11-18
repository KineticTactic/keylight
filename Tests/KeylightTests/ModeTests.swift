import XCTest
@testable import Keylight

final class ModeTests: XCTestCase {
    func testTempoFromPlaybackPulses() throws {
        let rate = 48_000.0
        let layer = FactoryMode.tempo.makeScene().layers[0]
        for bpm in [90.0, 120, 150] {
            let analyzer = AudioSpectrum()
            analyzer.configure([AudioRoute(layer)])
            let interval = Int((rate * 60 / bpm).rounded())
            var beat = Array(repeating: Float.zero, count: interval)
            for i in 0..<3200 {
                let t = Double(i) / rate
                beat[i] = Float(0.6 * sin(2 * .pi * 80 * t) * exp(-t * 45))
            }
            for n in 0..<12 {
                analyzer.ingest(n == 7 ? Array(repeating: 0, count: interval) : beat, rate: rate)
            }
            XCTAssertEqual(try XCTUnwrap(analyzer.readings[layer.id]?.bpm), bpm, accuracy: 4)
            analyzer.ingest(.init(repeating: 0, count: 144000), rate: rate)
            XCTAssertNil(analyzer.readings[layer.id]?.bpm)
        }
    }

    func testTempoWaveIsContinuousOnLockAndRelease() {
        var motion = RhythmMotion()
        var previous = 0.0
        for i in 0..<360 {
            let bpm: Double? = (30..<240).contains(i) ? 150 : nil
            let next = motion.advance(by: 1.0 / 30, bpm: bpm, onsetAge: Double(i % 12) / 30)
            XCTAssertGreaterThan(next, previous)
            XCTAssertLessThan(next - previous, 0.11)
            previous = next
        }
        var tracker = TempoTracker()
        for i in 0..<10 { tracker.hit(at: Double(i) * 0.5) }
        for i in 1...12 { tracker.hit(at: 4.5 + Double(i) * 0.4) }
        XCTAssertEqual(tracker.bpm ?? 0, 150, accuracy: 2)
    }

    func testFactoryLibraryMigrationPreservesCustomWork() {
        let oldAmbient = LightingScene(name: "Northern lights")
        var editedScreen = LightingScene(name: "Screen + bass", layers: [Layer(effect: .screen), Layer(effect: .bass, keys: [75])])
        editedScreen.layers[0].keys = [30, 31]
        var percussion = LightingScene.drumScene
        percussion.name = "Drum perimeter"
        percussion.layers[0].audio.gain = 2.75
        var library = Library(scenes: [oldAmbient, editedScreen, percussion], selected: percussion.id)
        library.updateCatalog()
        XCTAssertEqual(library.selected, percussion.id)
        XCTAssertTrue(library.scenes.contains(editedScreen))
        XCTAssertFalse(library.scenes.contains(oldAmbient))
        let upgraded = library.scenes.first { $0.id == percussion.id }
        XCTAssertEqual(upgraded?.name, FactoryMode.percussion.title)
        XCTAssertEqual(upgraded?.layers, percussion.layers)
        let once = library
        library.updateCatalog()
        XCTAssertEqual(library, once)
        var clean = Library(scenes: [oldAmbient], selected: oldAmbient.id)
        clean.updateCatalog()
        XCTAssertEqual(clean.selected, FactoryMode.aurora.id)
    }

    func testFinishedModesRenderDistinctFrames() {
        let previews = FactoryMode.thumbnails
        XCTAssertEqual(previews.count, FactoryMode.allCases.count)
        var encoded = Set<Data>()
        for colors in previews.values {
            XCTAssertEqual(colors.count, 82)
            XCTAssertGreaterThan(Set(colors.map { Data($0.bytes) }).count, 4)
            encoded.insert(Data(colors.flatMap(\.bytes)))
        }
        XCTAssertEqual(encoded.count, previews.count)
        for mode in [FactoryMode.aurora, .meteor, .ember] {
            let scene = mode.makeScene()
            XCTAssertEqual(scene.inputLabel, "Ambient")
            let a = EffectEngine.render(scene, time: 0, signals: Signals())
            let b = EffectEngine.render(scene, time: 2, signals: Signals())
            XCTAssertNotEqual(a, b)
        }
    }

    func testEqualizerHeightAndScreenWash() {
        let towers = FactoryMode.towers.makeScene()
        let bars = towers.layers[1]
        let silence = EffectEngine.render(towers, time: 0, signals: Signals())
        let input = Signals(audio: [bars.id: AudioReading(levels: [0.5, 0, 0, 0])])
        let raised = EffectEngine.render(towers, time: 0, signals: input)
        XCTAssertNotEqual(raised[72], silence[72])  // bottom of left band
        XCTAssertEqual(raised[0], silence[0])      // top of same band
        XCTAssertEqual(raised[80], silence[80])    // silent treble
        let cinema = FactoryMode.cinema.makeScene()
        let screen = Board.keys.map { $0.x < 8 ? RGB(r: 1, g: 0, b: 0) : RGB(r: 0, g: 0, b: 1) }
        let wash = EffectEngine.render(cinema, time: 0, signals: Signals(screen: screen))
        XCTAssertGreaterThan(wash[0].r, wash[0].b)
        XCTAssertGreaterThan(wash[80].b, wash[80].r)
    }
}
