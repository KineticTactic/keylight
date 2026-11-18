import Combine
import XCTest
@testable import Keylight

final class StatusMenuTests: XCTestCase {
    @MainActor func testOnlyMenuEditsInvalidateTheStatusMenu() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = Studio(file: directory.appendingPathComponent("Scenes.json"))
        defer { studio.finish() }
        let menu = StatusMenuState(studio: studio)
        var changes = 0
        let observer = menu.objectWillChange.sink { changes += 1 }
        defer { observer.cancel() }

        XCTAssertEqual(menu.modes.map(\.id), studio.scenes.map(\.id))
        for i in 0..<90 {
            studio.frame[0].r = Double(i) / 90
            studio.meter[0] = Double(i) / 90
            studio.beatMonitors = [:]
        }
        studio.scene.brightness = 0.25
        XCTAssertEqual(changes, 0)

        studio.duplicate()
        XCTAssertEqual(menu.modes.last?.id, studio.selected)
        XCTAssertEqual(menu.selected, studio.selected)
        studio.scene.name = "After hours"
        XCTAssertEqual(menu.modes.last?.name, "After hours")
        studio.paused.toggle()
        XCTAssertEqual(menu.paused, studio.paused)
        XCTAssertEqual(changes, 4)
    }
}
