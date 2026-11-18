import XCTest
@testable import Keylight

final class BassEchoTests: XCTestCase {
    func testRapidKicksKeepTravelingBetweenDisplayFrames() throws {
        let scene = FactoryMode.bloom.makeScene()
        let layer = try XCTUnwrap(scene.layers.last)
        let analyzer = AudioSpectrum()
        analyzer.configure([AudioRoute(layer)])
        let rate = 48_000.0
        let interval = 3072 // 64 ms
        var burst = [Float](repeating: 0, count: 10 * interval)
        for hit in 0..<10 {
            for i in 0..<1024 {
                let t = Double(i) / rate
                burst[hit * interval + i] = Float(0.8 * sin(2 * .pi * 90 * t) * exp(-90 * t))
            }
        }
        analyzer.ingest(burst, rate: rate)
        let input = try XCTUnwrap(analyzer.readings[layer.id])
        XCTAssertEqual(input.echoHits.count, 10)
        var single = input
        single.echoHits = Array(input.echoHits.suffix(1))
        func render(_ value: AudioReading) -> [RGB] {
            EffectEngine.render(scene, time: 0, signals: Signals(audio: [layer.id: value]))
        }
        let outerKey = 13 // Delete, near the opposite corner from the spacebar
        XCTAssertGreaterThan(render(input)[outerKey].b, render(single)[outerKey].b + 0.25)
        analyzer.ingest(.init(repeating: 0, count: 48_000), rate: rate)
        XCTAssertTrue(try XCTUnwrap(analyzer.readings[layer.id]).echoFronts(for: layer).isEmpty)
    }

    func testTravelDirectionsAndPersistence() throws {
        let scene = FactoryMode.bloom.makeScene()
        var layer = try XCTUnwrap(scene.layers.last)
        func distance(_ direction: EchoDirection, _ keyID: Int) -> Double {
            let key = Board.keys[keyID]
            return direction.distance(x: (key.x + key.width / 2) / Board.width, y: (key.y + 0.5) / Board.height)
        }
        for (direction, start, end) in [(EchoDirection.outward, 75, 81), (.inward, 81, 75),
                                        (.right, 0, 81), (.left, 81, 0), (.down, 0, 75), (.up, 75, 0)] {
            XCTAssertEqual(distance(direction, start), 0, accuracy: 0.0001)
            XCTAssertEqual(distance(direction, end), 1, accuracy: 0.0001)
            layer.echoDirection = direction
            let saved = try JSONEncoder().encode(layer)
            XCTAssertEqual(try JSONDecoder().decode(Layer.self, from: saved).echoDirection, direction)
        }
    }
}
