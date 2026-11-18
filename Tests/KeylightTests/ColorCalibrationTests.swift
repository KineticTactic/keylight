import XCTest
@testable import Keylight

final class ColorCalibrationTests: XCTestCase {
    func testPaletteCoversWholeCubeAndUntouchedProfileIsIdentity() {
        let targets = CalibrationTarget.essentials + CalibrationTarget.refinements
        XCTAssertEqual(targets.sorted(), Array(1...26))
        let frame = targets.map(CalibrationTarget.color) + [RGB(r: 0.132, g: 0.555, b: 0.901)]
        XCTAssertEqual(ColorLUT(ColorCalibration()).apply(to: frame), frame)
    }

    func testWhiteMatchTracksNeutralRampAndLeavesPrimaryRedAlone() {
        let white = RGB(r: 1, g: 0.61, b: 0.48)
        let profile = ColorCalibration(matches: [26: white])
        let lut = ColorLUT(profile)
        for gray in [0.0, 0.15, 0.50, 128.0 / 255, 0.65, 1.0] {
            let output = lut.apply(to: [RGB(r: gray, g: gray, b: gray)])[0]
            XCTAssertEqual(output.r, gray, accuracy: 1e-10)
            XCTAssertEqual(output.g, gray * white.g, accuracy: 1e-10)
            XCTAssertEqual(output.b, gray * white.b, accuracy: 1e-10)
        }
        XCTAssertEqual(lut.apply(to: [CalibrationTarget.color(18)]), [CalibrationTarget.color(18)])
    }

    func testFineTuningPassesThroughMatchesAndBlendsNearbyColors() {
        let orange = CalibrationTarget.color(21), red = CalibrationTarget.color(18)
        let match = RGB(r: 0.8, g: 0.3, b: 0.02)
        var profile = ColorCalibration(matches: [21: match])
        let frame = [orange, red.mix(orange, 0.5), .black]
        let result = ColorLUT(profile).apply(to: frame)
        XCTAssertEqual(result[0], match)
        XCTAssertEqual(result[1].bytes, red.mix(match, 0.5).bytes)
        XCTAssertEqual(result[2], .black)
        profile.enabled = false
        XCTAssertEqual(ColorLUT(profile).apply(to: frame), frame)
    }

    @MainActor
    func testDraftPatchBypassesProfileAndRestoresSceneAndPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Scenes.json")
        try JSONEncoder().encode(Library.initial()).write(to: file)
        let studio = Studio(file: file)
        let white = CalibrationTarget.color(26)
        let correction = RGB(r: 1, g: 0.64, b: 0.38)
        studio.frame = [white, .black]
        XCTAssertEqual(studio.physicalFrame(), studio.frame)
        studio.calibration = ColorCalibration(matches: [26: correction])
        XCTAssertEqual(studio.physicalFrame(), [correction, .black])
        studio.paused = true
        studio.calibrationPatch = white
        XCTAssertEqual(studio.physicalFrame(), [white, white])
        studio.calibrationPatch = nil
        XCTAssertEqual(studio.physicalFrame(), [correction, .black])
        XCTAssertEqual(studio.frame, [white, .black])
        studio.calibration.enabled = false
        XCTAssertEqual(studio.physicalFrame(), studio.frame)
        studio.finish()
        let reopened = Studio(file: file)
        XCTAssertEqual(reopened.calibration, studio.calibration)
        reopened.frame = [white, .black]
        XCTAssertEqual(reopened.physicalFrame(), reopened.frame)
        reopened.calibration.enabled = true
        XCTAssertEqual(reopened.physicalFrame(), [correction, .black])
        reopened.finish()
    }
}
