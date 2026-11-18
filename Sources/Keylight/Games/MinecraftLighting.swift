import Foundation

struct MinecraftLighting {
    var damage = 0.0
    var flightBlend = 0.0
    var speed = 0.0
    var phase = 0.0
    var boostAge = Double.infinity
    var portal = 0.0
    var arrivalAge = Double.infinity

    func color(over screen: RGB, key: Key) -> RGB {
        let x = (key.x + key.width / 2) / Board.width
        let y = (key.y + 0.5) / Board.height
        var color = screen
        let left = key.x == 0
        if (left || key.x + key.width == Board.width) && (flightBlend > 0 || boostAge < 0.9) {
            let tint = left ? RGB(r: 0.08, g: 1, b: 0.06) : RGB(r: 0, g: 0.95, b: 1)
            let crest = (1 + cos(phase - 2 * .pi * y)) / 2
            let brightness = 0.22 + 0.78 * crest * crest
            color = color.mix(RGB.black.mix(tint, brightness), flightBlend)
            if boostAge < 0.9 {
                let distance = (y - (boostAge / 0.9 * 1.4 - 0.2)) / 0.16
                color = color.mix(tint, exp(-distance * distance))
            }
        }
        let violet = RGB(r: 0.64, g: 0.14, b: 1)
        let depth = 2 * min(x, 1 - x, y, 1 - y)
        if portal > 0 {
            let front = min(1, max(0, (portal * 1.25 - depth + 0.1) / 0.20))
            color = color.mix(violet, 0.88 * front * min(1, portal * 8))
        }
        if arrivalAge < 1.2 {
            // Reveal the destination from the center out, leaving the rim violet last.
            let remaining = 1 - arrivalAge / 1.2
            let veil = min(1, max(0, (remaining * 1.7 - depth * 0.7)))
            color = color.mix(violet, 0.90 * veil)
        }
        return color.mix(RGB(r: 1, g: 0, b: 0), damage)
    }
}

/// The game publishes motion at 10 Hz. The studio interpolates at its render rate.
struct MinecraftMotion {
    private var lastSample = -Double.infinity
    private var lastFrame: Double?
    private var flight = 0
    private var charge = 0
    private var boost = -Double.infinity
    private var arrival = -Double.infinity
    private var lighting = MinecraftLighting()

    mutating func receive(_ message: String, at now: Double) {
        switch message {
        case "keylight:boost:1": boost = now
        case "keylight:arrival:1":
            arrival = now
            charge = 0
            lighting.portal = 0
        default:
            let fields = message.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 5, fields[0] == "keylight", fields[1] == "motion", fields[2] == "1",
                  let speed = UInt8(fields[3]), let portal = UInt8(fields[4]) else { return }
            flight = Int(speed)
            charge = Int(portal)
            lastSample = now
        }
    }

    mutating func frame(at now: Double) -> MinecraftLighting {
        let dt = min(1, max(0, now - (lastFrame ?? now - 1.0 / 30)))
        lastFrame = now
        let fresh = now - lastSample < 0.5
        let flying = fresh && flight > 0
        let ease = 1 - exp(-dt * 12)
        lighting.flightBlend += ((flying ? 1 : 0) - lighting.flightBlend) * ease
        lighting.speed += ((flying ? Double(flight - 1) / 254 : 0) - lighting.speed) * ease
        lighting.portal += ((fresh ? Double(charge) / 255 : 0) - lighting.portal) * ease
        if !flying && lighting.flightBlend < 0.001 { lighting.flightBlend = 0 }
        if (!fresh || charge == 0) && lighting.portal < 0.001 { lighting.portal = 0 }
        lighting.phase = (lighting.phase + dt * lighting.speed * 1.4 * 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        lighting.boostAge = now - boost
        lighting.arrivalAge = now - arrival
        return lighting
    }
}
