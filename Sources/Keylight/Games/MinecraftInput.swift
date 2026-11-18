import Darwin
import Foundation

/// Read on the studio's render thread. Only the active Minecraft capture owns a socket.
final class MinecraftInput {
    static let port: UInt16 = 49375
    private var motion = MinecraftMotion()
    private let socketFD: Int32
    private var lastHit: Double?
    private var waitingForOutput = false

    init(port: UInt16 = MinecraftInput.port) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            close(fd)
            throw error
        }
        socketFD = fd
    }

    deinit { close(socketFD) }

    func snapshot(at now: Double, outputReady: Bool) -> MinecraftLighting {
        var buffer = [UInt8](repeating: 0, count: 48)
        for _ in 0..<32 {
            let length = buffer.withUnsafeMutableBytes { recv(socketFD, $0.baseAddress, $0.count, MSG_DONTWAIT) }
            if length < 0 { break }
            guard length < buffer.count, let message = String(bytes: buffer.prefix(length), encoding: .ascii) else { continue }
            if message == "keylight:hit:1" {
                lastHit = now
                waitingForOutput = true
            } else {
                motion.receive(message, at: now)
            }
        }
        var result = motion.frame(at: now)
        guard let hit = lastHit else { return result }
        // Keep the peak for the first available write on the slower radio transport.
        if waitingForOutput && now - hit < 0.75 {
            if outputReady { waitingForOutput = false; lastHit = now }
            result.damage = 1
            return result
        }
        waitingForOutput = false
        result.damage = min(1, max(0, (0.30 - (now - hit)) / 0.25))
        return result
    }
}
