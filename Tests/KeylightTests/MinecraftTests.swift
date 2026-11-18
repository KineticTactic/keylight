import Darwin
import XCTest
@testable import Keylight

final class MinecraftTests: XCTestCase {
    func testHitOverridesEveryKeyThenReturnsToCurrentDisplay() {
        let scene = FactoryMode.minecraft.makeScene()
        XCTAssertEqual(scene.inputLabel, "Screen")
        let screen = Board.keys.map { RGB(r: 0, g: $0.x / Board.width, b: $0.y / Board.height) }
        let red = RGB(r: 1, g: 0, b: 0)
        var signals = Signals(screen: screen)
        func render() -> [RGB] { EffectEngine.render(scene, time: 0, signals: signals) }
        XCTAssertEqual(render(), screen.map { RGB.black.mix($0, scene.brightness) })
        signals.minecraft.damage = 1
        XCTAssertEqual(render(), Array(repeating: RGB.black.mix(red, scene.brightness), count: screen.count))
        signals.screen.reverse()
        signals.minecraft.damage = 0.5
        XCTAssertEqual(render(), signals.screen.map { RGB.black.mix($0.mix(red, 0.5), scene.brightness) })
        signals.minecraft.damage = 0
        XCTAssertEqual(render(), signals.screen.map { RGB.black.mix($0, scene.brightness) })
    }

    func testFlightFollowsSpeedAndReturnsToScreenAfterLostUpdates() {
        var slow = MinecraftMotion(), fast = MinecraftMotion()
        for tick in 0...10 {
            let now = Double(tick) / 10
            slow.receive("keylight:motion:1:1:0", at: now)
            fast.receive("keylight:motion:1:255:0", at: now)
            _ = slow.frame(at: now)
            _ = fast.frame(at: now)
        }
        let a = slow.frame(at: 1), b = fast.frame(at: 1)
        XCTAssertGreaterThan(b.flightBlend, 0.99)
        XCTAssertGreaterThan(b.speed, a.speed)
        XCTAssertNotEqual(b.phase, a.phase)
        XCTAssertEqual(a.phase, 0, accuracy: 1e-8)
        var half = MinecraftMotion()
        for tick in 0...10 {
            let now = Double(tick) / 10
            half.receive("keylight:motion:1:128:0", at: now)
            _ = half.frame(at: now)
        }
        let halfStart = half.frame(at: 1).phase
        let halfStep = (half.frame(at: 1.01).phase - halfStart + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        let fullStep = (fast.frame(at: 1.01).phase - b.phase + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        XCTAssertEqual(fullStep, halfStep * 2, accuracy: 1e-8)
        XCTAssertEqual(fast.frame(at: 2).flightBlend, 0)
        fast.receive("keylight:motion:1:300:0", at: 2.1)
        XCTAssertEqual(fast.frame(at: 2.1).flightBlend, 0)
    }

    func testElytraRipplesMoveDownOnlyTheTwoOuterColumns() {
        let scene = FactoryMode.minecraft.makeScene()
        let left: Set<Int> = [0, 14, 29, 44, 58, 72]
        let right: Set<Int> = [81, 28, 43, 57, 71, 80]
        let screen = Board.keys.map { RGB(r: 0.6, g: Double($0.id) / 128, b: 0.35) }
        var signals = Signals(screen: screen)
        let base = EffectEngine.render(scene, time: 0, signals: signals)
        signals.minecraft.flightBlend = 1
        // Put the crest first at Esc, then at Tab.
        signals.minecraft.phase = 2 * .pi * 0.5 / Board.height
        let top = EffectEngine.render(scene, time: 0, signals: signals)
        signals.minecraft.phase = 2 * .pi * 2.75 / Board.height
        let lower = EffectEngine.render(scene, time: 0, signals: signals)
        XCTAssertGreaterThan(top[0].g, lower[0].g)
        XCTAssertGreaterThan(lower[29].g, top[29].g)
        XCTAssertGreaterThan(lower[43].b, top[43].b)
        signals.minecraft.boostAge = 0.45
        let boosted = EffectEngine.render(scene, time: 0, signals: signals)
        for id in left { XCTAssertGreaterThan(top[id].g, top[id].b * 8) }
        for id in right { XCTAssertGreaterThan(top[id].b, 0.1); XCTAssertEqual(top[id].r, 0, accuracy: 1e-8) }
        for key in Board.keys where !left.contains(key.id) && !right.contains(key.id) {
            XCTAssertEqual(top[key.id], base[key.id])
            XCTAssertEqual(boosted[key.id], base[key.id])
        }
    }

    func testPortalRecedesOnExitAndArrivalRevealsTheCenterFirst() {
        var motion = MinecraftMotion()
        motion.receive("keylight:motion:1:0:100", at: 0)
        _ = motion.frame(at: 0)
        let charging = motion.frame(at: 0.25)
        let rim = charging.color(over: .black, key: Board.keys[44])
        XCTAssertGreaterThan(rim.b, 0.6)
        XCTAssertEqual(charging.color(over: .black, key: Board.keys[50]), .black)
        motion.receive("keylight:motion:1:0:0", at: 0.25)
        XCTAssertLessThan(motion.frame(at: 0.45).portal, charging.portal)
        motion.receive("keylight:arrival:1", at: 0.5)
        let arrival = motion.frame(at: 0.5)
        XCTAssertGreaterThan(arrival.color(over: .black, key: Board.keys[50]).b, 0.8)
        let halfway = motion.frame(at: 1.1)
        XCTAssertLessThan(halfway.color(over: .black, key: Board.keys[50]).b,
                          halfway.color(over: .black, key: Board.keys[44]).b)
        XCTAssertEqual(motion.frame(at: 2).color(over: rim, key: Board.keys[29]), rim)
    }

    func testRocketPulseTravelsAndDamageTakesPriority() {
        var motion = MinecraftMotion()
        motion.receive("keylight:boost:1", at: 0)
        let early = motion.frame(at: 0.18)
        let late = motion.frame(at: 0.72)
        let topLeft = Board.keys[0], bottomRight = Board.keys[80]
        XCTAssertGreaterThan(early.color(over: .black, key: topLeft).g,
                             late.color(over: .black, key: topLeft).g)
        XCTAssertGreaterThan(late.color(over: .black, key: bottomRight).b,
                             early.color(over: .black, key: bottomRight).b)
        motion.receive("keylight:boost:1", at: 0.8)
        XCTAssertEqual(motion.frame(at: 0.82).boostAge, 0.02, accuracy: 1e-6)
        var hit = late
        hit.damage = 1
        XCTAssertEqual(hit.color(over: .black, key: bottomRight), RGB(r: 1, g: 0, b: 0))
    }

    func testLoopbackHitsRetriggerAndWaitForRadioOutput() throws {
        // Use a separate port from the running app.
        var port = UInt16.random(in: 50000...60000)
        var listener: MinecraftInput?
        for _ in 0..<10 {
            do { listener = try MinecraftInput(port: port); break }
            catch let error as POSIXError where error.code == .EADDRINUSE { port += 1 }
        }
        let input = try XCTUnwrap(listener)
        let sender = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(sender, 0)
        defer { close(sender) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        func send(_ message: String) {
            let sent = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { dest in
                    Array(message.utf8).withUnsafeBytes {
                        sendto(sender, $0.baseAddress, $0.count, 0, dest, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            XCTAssertEqual(sent, message.utf8.count)
        }
        func awaitHit(at time: Double, outputReady: Bool) -> Double {
            let deadline = ProcessInfo.processInfo.systemUptime + 0.5
            repeat {
                let strength = input.snapshot(at: time, outputReady: outputReady).damage
                if strength == 1 { return strength }
                Thread.sleep(forTimeInterval: 0.001)
            } while ProcessInfo.processInfo.systemUptime < deadline
            return input.snapshot(at: time, outputReady: outputReady).damage
        }
        send("keylight:hit:1-extra")
        send("unrelated")
        XCTAssertEqual(input.snapshot(at: 10, outputReady: true).damage, 0)
        send("keylight:hit:1")
        XCTAssertEqual(awaitHit(at: 10.01, outputReady: false), 1)
        XCTAssertEqual(input.snapshot(at: 10.25, outputReady: true).damage, 1)
        XCTAssertEqual(input.snapshot(at: 10.45, outputReady: true).damage, 0.4, accuracy: 0.0001)
        send("keylight:hit:1")
        XCTAssertEqual(awaitHit(at: 10.47, outputReady: true), 1)
        XCTAssertEqual(input.snapshot(at: 10.80, outputReady: true).damage, 0)
    }
}
