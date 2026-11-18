import Foundation
import IOKit.hid

struct LightingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// URX's SignalRGB streaming extension on the vendor HID collection.
// macOS takes the report ID separately. The payload is exactly 32 bytes.
enum Wire {
    static func report(_ payload: [UInt8]) -> [UInt8] {
        precondition(payload.count <= 32)
        return payload + Array(repeating: 0, count: 32 - payload.count)
    }

    static func frames(_ colors: [RGB], previous: [RGB]) -> [[UInt8]] {
        precondition(colors.count == Board.keys.count)
        var packets: [[UInt8]] = []
        for start in stride(from: 0, to: colors.count, by: 9) {
            let end = min(start + 9, colors.count)
            let span = start..<end
            if previous.count == colors.count && previous[span] == colors[span] { continue }
            packets.append(report([0x24, UInt8(start), UInt8(span.count)] + colors[span].flatMap(\.bytes)))
        }
        return packets
    }
}

enum Core75Link: Int, CaseIterable {
    case wired = 0x3130
    case receiver = 0x3002

    var label: String { self == .wired ? "USB cable" : "2.4 GHz receiver" }
    var matching: [String: Any] {
        [kIOHIDVendorIDKey: 0x36B0, kIOHIDProductIDKey: rawValue,
         kIOHIDPrimaryUsagePageKey: 0xFF60, kIOHIDPrimaryUsageKey: 0x61,
         kIOHIDTransportKey: "USB"]
    }
}

enum ConnectionChoice: String, CaseIterable {
    case automatic = "Automatic", wired = "USB cable", receiver = "2.4 GHz receiver"

    var links: [Core75Link] {
        switch self {
        case .automatic: return [.wired, .receiver]
        case .wired: return [.wired]
        case .receiver: return [.receiver]
        }
    }
}

// Accessed exclusively on the USB queue, or synchronously by the CLI.
final class Keyboard: @unchecked Sendable {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private var previous: [RGB] = []
    private var streaming = false
    private var via = false
    private var restoration: [[UInt8]] = []
    private var activeLink = Core75Link.wired
    var backend: String { "\(activeLink.label) · " + (via ? "VIA · 81 keys" : "RGB stream · 82 LEDs") }
    private var replies = [[UInt8]]()

    func devices(_ choice: ConnectionChoice = .automatic) -> [(Core75Link, IOHIDDevice)] {
        IOHIDManagerSetDeviceMatchingMultiple(manager, choice.links.map(\.matching) as CFArray)
        let found = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return choice.links.flatMap { link in
            found.compactMap { device in
                let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
                return product == link.rawValue ? (link, device) : nil
            }
        }
    }

    func connect(_ choice: ConnectionChoice = .automatic, probeOnly: Bool = false) throws {
        let candidates = devices(choice)
        guard !candidates.isEmpty else {
            throw LightingError("Core75 unavailable (\(choice.rawValue)). Plug in the matching cable or receiver and select that mode on the keyboard.")
        }
        var failures: [String] = []
        for (link, candidate) in candidates {
            activeLink = link
            do {
                try open(candidate, probeOnly: probeOnly)
                return
            } catch { failures.append("\(link.label): \(error.localizedDescription)") }
        }
        throw LightingError(failures.joined(separator: "\n"))
    }

    private func open(_ found: IOHIDDevice, probeOnly: Bool) throws {
        let options: IOOptionBits = probeOnly ? 0 : IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        guard IOHIDDeviceOpen(found, options) == kIOReturnSuccess else {
            throw LightingError("Cannot open the lighting interface. Quit ColorHoster or other keyboard lighting apps, then reconnect.")
        }
        device = found
        do {
            try withReader(found) { try checkFirmware() }
            if probeOnly { close(); return }
            streaming = true
            if via {
                try writePackets([Wire.report([7] + VIA.mode + [255]), Wire.report([7] + VIA.brightness + [255])])
            } else {
                try send(Wire.report([0x25]))
            }
        } catch {
            close()
            throw error
        }
    }

    private func withReader<T>(_ device: IOHIDDevice, _ action: () throws -> T) rethrows -> T {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        let loop = CFRunLoopGetCurrent()!
        IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 32, { ctx, result, _, _, _, bytes, length in
            guard result == kIOReturnSuccess, let ctx, length > 0 else { return }
            let owner = Unmanaged<Keyboard>.fromOpaque(ctx).takeUnretainedValue()
            owner.replies.append(Array(UnsafeBufferPointer(start: bytes, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 32, nil, nil)
            buffer.deallocate()
            replies.removeAll()
        }
        return try action()
    }

    private func checkFirmware() throws {
        if activeLink == .wired, try query([0x22], matching: [0x22, 1, 0, 6]) != nil,
           try query([0x27], matching: [0x27, 82]) != nil {
            via = false
            return
        }
        via = true
        // Snapshot each volatile setting before switching modes. Keep the mode
        // last in restoration so an existing direct scene is restored intact.
        restoration = try viaState()
    }

    private func viaState() throws -> [[UInt8]] {
        var saved: [[UInt8]] = []
        for header in VIA.ranges() + [VIA.brightness, VIA.mode] {
            let request = [UInt8(8)] + header
            guard let response = try query(request, matching: request), response.count == 32 else {
                throw LightingError("No VIA lighting reply. Wake the keyboard, check its mode and pairing, then reconnect.")
            }
            let length = header.count == 2 ? 1 : Int(header[3]) * (header[1] == 1 ? 2 : 1)
            saved.append(Wire.report([7] + header + response.dropFirst(request.count).prefix(length)))
        }
        return saved
    }

    private func query(_ request: [UInt8], matching prefix: [UInt8]) throws -> [UInt8]? {
        let attempts = activeLink == .receiver ? 2 : 1
        for _ in 0..<attempts {
            replies.removeAll()
            try send(Wire.report(request))
            let deadline = ProcessInfo.processInfo.systemUptime + 0.6
            while ProcessInfo.processInfo.systemUptime < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.012, true)
                if let match = replies.first(where: { $0.starts(with: prefix) }) { return match }
            }
        }
        return nil
    }

    private func send(_ buffer: [UInt8]) throws {
        guard let device else { throw LightingError("Keyboard disconnected.") }
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer, buffer.count)
        guard result == kIOReturnSuccess else {
            throw LightingError("\(activeLink.label) write failed (\(result)). Check the connection and reconnect.")
        }
    }

    private func writePackets(_ packets: [[UInt8]]) throws {
        guard !packets.isEmpty else { return }
        guard activeLink == .receiver, let device else {
            for packet in packets { try send(packet) }
            return
        }
        // The USB dongle can accept a host write before the keyboard receives
        // it. Wait for the matching VIA acknowledgement before the next write.
        try withReader(device) {
            for packet in packets {
                let headerSize = packet[1] == 0 ? 5 : 4
                let prefix = Array(packet.prefix(headerSize))
                guard try query(packet, matching: prefix) != nil else {
                    throw LightingError("The 2.4 GHz keyboard stopped acknowledging lighting updates. Wake it and reconnect.")
                }
            }
        }
    }

    func display(_ colors: [RGB]) throws {
        guard streaming else { throw LightingError("Keyboard output is off.") }
        let packets = via ? VIA.frames(colors, previous: previous) : Wire.frames(colors, previous: previous)
        try writePackets(packets)
        previous = colors
    }

    // Runs only when explicitly invoked from the command line.
    func testKeys(_ choice: ConnectionChoice = .automatic) throws {
        try connect(choice)
        print("Testing \(backend)")
        defer { close() }
        guard let active = device else { throw LightingError("Keyboard disconnected.") }
        let original = restoration
        let clock = ProcessInfo.processInfo
        let start = clock.systemUptime
        let scene = LightingScene()
        for index in 0..<90 {
            let time = Double(index) / 30
            try display(EffectEngine.render(scene, time: time, signals: Signals()))
            let wait = start + Double(index + 1) / 30 - clock.systemUptime
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        print(String(format: "Sent 90 wave frames at %.1f fps", 90 / (clock.systemUptime - start)))
        var markers = Array(repeating: RGB.black, count: Board.keys.count)
        markers[0] = RGB(r: 0.7, g: 0, b: 0)
        markers[75] = RGB(r: 0, g: 0.7, b: 0)
        markers[80] = RGB(r: 0, g: 0, b: 0.7)
        try display(markers)
        Thread.sleep(forTimeInterval: 2)
        if via {
            let state = try withReader(active) { try viaState() }
            let expected = VIA.frames(markers, previous: [])
            guard Array(state.prefix(expected.count)) == expected else {
                throw LightingError("The keyboard returned different per-key colors than the test pattern.")
            }
            print("Read back the marker pattern across all 81 per-key slots.")
            // Verify restoration before relinquishing the exclusive handle.
            try writePackets(original)
            let restored = try withReader(active) { try viaState() }
            guard restored == original else { throw LightingError("Lighting state restoration could not be verified.") }
            streaming = false
            print("Verified original colors, global brightness and effect after restoration.")
        }
    }

    func disconnect() throws {
        guard let device else { return }
        defer {
            IOHIDDeviceClose(device, 0)
            self.device = nil
            streaming = false
            restoration = []
            previous = []
        }
        if streaming {
            try writePackets(via ? restoration : [Wire.report([0x26])])
            if activeLink == .receiver {
                let restored = try withReader(device) { try viaState() }
                guard restored == restoration else {
                    throw LightingError("Disconnected. Could not verify restoration of the prior wireless lighting.")
                }
            }
        }
    }

    func close() { try? disconnect() }
}
