import AVFoundation
import XCTest
@testable import Keylight

final class LightingTests: XCTestCase {
    func testSpectrumMiddleColorSurvivesSaveAndBlendsAcrossPhysicalKeys() throws {
        var layer = Layer(effect: .spectrum, color: RGB(r: 1, g: 0, b: 0), secondary: RGB(r: 0, g: 0, b: 1))
        let legacy = try JSONEncoder().encode(layer)
        XCTAssertNil(try JSONDecoder().decode(Layer.self, from: legacy).middleColor)
        layer.middle = RGB(r: 0, g: 1, b: 0)
        let saved = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer))
        XCTAssertEqual(saved.middleColor, layer.middle)
        let scene = LightingScene(layers: [saved], brightness: 1)
        let signal = Signals(audio: [layer.id: AudioReading(levels: [1, 1, 1, 1])])
        let frame = EffectEngine.render(scene, time: 0, signals: signal)
        // Q, U and ] have physical centers at 2, 8 and 13 key units on this board.
        XCTAssertEqual(frame[30], RGB(r: 0.75, g: 0.25, b: 0))
        XCTAssertEqual(frame[36], layer.middle)
        XCTAssertEqual(frame[41], RGB(r: 0, g: 0.375, b: 0.625))
    }

    func testLayoutAndStreamingPackets() {
        XCTAssertEqual(Board.keys.map(\.id), Array(0..<82))
        XCTAssertEqual(Board.keys[75].label, "Space")
        XCTAssertEqual(Board.keys[81].label, "Knob")
        let colors = Board.keys.map { RGB(r: Double($0.id) / 255, g: 0, b: 0) }
        let frames = Wire.frames(colors, previous: [])
        XCTAssertEqual(frames.count, 10)
        XCTAssertTrue(frames.allSatisfy { $0.count == 32 && $0[0] == 0x24 })
        XCTAssertEqual(Array(frames.last!.prefix(6)), [0x24, 81, 1, 81, 0, 0])
        XCTAssertTrue(Wire.frames(colors, previous: colors).isEmpty)
    }

    func testVIAPayloadsAndBounds() {
        let colors = Array(repeating: RGB(r: 0, g: 1, b: 0), count: 82)
        let frames = VIA.frames(colors, previous: [])
        XCTAssertEqual(frames.count, 10)
        XCTAssertTrue(frames.allSatisfy { $0.count == 32 && $0[0] == 7 && $0[1] == 0 && Int($0[3]) + Int($0[4]) <= 81 })
        XCTAssertEqual(Array(frames[0].prefix(7)), [7, 0, 1, 0, 13, 85, 255])
        XCTAssertEqual(Array(frames.last!.prefix(6)), [7, 0, 2, 54, 27, 255])
        XCTAssertTrue(VIA.frames(colors, previous: colors).isEmpty)
    }

    func testConnectionSelectionAndReceiverDefinition() {
        XCTAssertEqual(ConnectionChoice.automatic.links, [.wired, .receiver])
        XCTAssertEqual(ConnectionChoice.receiver.links, [.receiver])
        XCTAssertEqual(ConnectionChoice.wired.links, [.wired])
        let match = Core75Link.receiver.matching
        XCTAssertEqual(match["VendorID"] as? Int, 0x36b0)
        XCTAssertEqual(match["ProductID"] as? Int, 0x3002)
        XCTAssertEqual(match["PrimaryUsagePage"] as? Int, 0xff60)
        XCTAssertEqual(match["PrimaryUsage"] as? Int, 0x61)
    }

    func testVIAOnlySendsChannelsChangedOnTheWire() {
        let red = Array(repeating: RGB(r: 0.9, g: 0, b: 0), count: 82)
        let dim = Array(repeating: RGB(r: 0.45, g: 0, b: 0), count: 82)
        let blue = Array(repeating: RGB(r: 0, g: 0, b: 0.9), count: 82)
        XCTAssertEqual(VIA.frames(dim, previous: red).map { $0[2] }, [2, 2, 2])
        XCTAssertEqual(VIA.frames(blue, previous: red).map { $0[2] }, Array(repeating: 1, count: 7))
    }

    func testMaskedBassOverlayPreservesScreenElsewhere() {
        let red = RGB(r: 1, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 1)
        let scene = LightingScene(layers: [Layer(effect: .screen), Layer(effect: .bass, color: red, keys: [75])], brightness: 0.5)
        let signals = Signals(screen: Array(repeating: blue, count: 82), audio: [scene.layers[1].id: AudioReading(levels: [1, 0, 0, 0])])
        let frame = EffectEngine.render(scene, time: 1, signals: signals)
        XCTAssertEqual(frame[75], RGB(r: 0.5, g: 0, b: 0))
        XCTAssertEqual(frame[0], RGB(r: 0, g: 0, b: 0.5))
    }

    func testScreenSamplesFollowPhysicalKeyPositions() throws {
        var image: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 128, 80, kCVPixelFormatType_32BGRA, nil, &image), kCVReturnSuccess)
        let buffer = try XCTUnwrap(image)
        CVPixelBufferLockBaseAddress(buffer, [])
        let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<80 {
            for x in 0..<128 {
                let i = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                ptr[i] = x < 64 ? 0 : 255
                ptr[i + 1] = 0
                ptr[i + 2] = x < 64 ? 255 : 0
                ptr[i + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let capture = Capture()
        capture.sampleScreen(buffer)
        XCTAssertEqual(capture.snapshot().screen[0], RGB(r: 0.65, g: 0, b: 0))
        XCTAssertEqual(capture.snapshot().screen[81], RGB(r: 0, g: 0, b: 0.65))
    }

    func testBassRespondsMoreToLowToneThanTreble() throws {
        func level(hz: Double) throws -> Double {
            let fmt = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096))
            pcm.frameLength = pcm.frameCapacity
            for i in 0..<4096 { pcm.floatChannelData![0][i] = 0.2 * Float(sin(2 * .pi * hz * Double(i) / 48000)) }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            XCTAssertEqual(CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil,
                refcon: nil, formatDescription: fmt.formatDescription, sampleCount: 4096, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample), noErr)
            let buffer = try XCTUnwrap(sample)
            XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(buffer, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                flags: 0, bufferList: pcm.audioBufferList), noErr)
            let capture = Capture()
            let layer = Layer(effect: .bass)
            capture.configure([AudioRoute(layer)])
            capture.sampleAudio(buffer)
            return try XCTUnwrap(capture.snapshot().audio[layer.id]).levels[0]
        }
        let bass = try level(hz: 60)
        XCTAssertGreaterThan(bass, 0.4)
        XCTAssertLessThan(try level(hz: 5000), bass * 0.1)
    }

    @MainActor func testEditedSceneSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Scenes.json")
        let studio = Studio(file: file)
        studio.duplicate()
        studio.scene.name = "Night"
        studio.scene.layers[0].keys = [75, 79]
        studio.finish()
        let restored = Studio(file: file)
        XCTAssertEqual(restored.scene, studio.scene)
        XCTAssertEqual(restored.scenes.count, FactoryMode.allCases.count + 1)
        restored.finish()
    }
}
