import Foundation

/// Compare recent attacks across several beats, including attacks separated by fills.
struct TempoTracker {
    static let expiry = 2.5
    private struct Hit {
        let time: Double
        let weight: Double
    }
    private var hits: [Hit] = []
    private(set) var bpm: Double?
    private(set) var confirmedAt = -Double.infinity

    mutating func hit(at time: Double, strength: Double = 1) {
        if let last = hits.last, time <= last.time || time - last.time >= Self.expiry {
            hits.removeAll()
            bpm = nil
            confirmedAt = -.infinity
        }
        hits.removeAll { time - $0.time > 6 }
        if hits.count >= 48 { hits.removeFirst() }
        hits.append(Hit(time: time, weight: max(0.08, min(1, strength))))
        guard hits.count >= 4 else { return }

        // An extra onset between two kicks does not remove their spacing
        // from this histogram. Count direct beat intervals most heavily.
        var votes = Array(repeating: 0.0, count: 181)
        var possible = 0.0
        var newestSupport = [Double]()
        for j in 1..<hits.count {
            let end = hits[j]
            let recency = exp((end.time - time) / 1.65)
            possible += recency * end.weight
            var best = Array(repeating: 0.0, count: 181)
            var interveningWeight = 0.0
            for i in (0..<j).reversed() {
                let gap = end.time - hits[i].time
                if gap > 2.85 { break }
                let sharedWeight = min(end.weight, hits[i].weight)
                // Skipping an equally strong attack favors half time. Skipping
                // a quiet fill between strong beats should cost much less.
                let weight = sharedWeight * (1 - 0.22 * min(1, interveningWeight / sharedWeight))
                interveningWeight = max(interveningWeight, hits[i].weight)
                for beats in 1...3 {
                    let span = Double(beats) * 60
                    let tolerance = 0.050 + 0.009 * Double(beats)
                    let minimum = max(65, Int(ceil(span / (gap + tolerance))))
                    let maximum = min(180, Int(floor(span / max(0.01, gap - tolerance))))
                    guard minimum <= maximum else { continue }
                    let importance = beats == 1 ? 1.0 : (beats == 2 ? 0.72 : 0.50)
                    for candidate in minimum...maximum {
                        let error = (gap - span / Double(candidate)) / tolerance
                        let fit = weight * importance * (1 - error * error)
                        best[candidate] = max(best[candidate], fit)
                    }
                }
            }
            if j == hits.count - 1 { newestSupport = best }
            for candidate in 65...180 { votes[candidate] += recency * best[candidate] }
        }
        guard let winner = (65...180).max(by: { votes[$0] < votes[$1] }) else { return }
        guard time - hits[0].time >= 2.7 * 60 / Double(winner) else { return }

        // Keep the current pulse when a competing subdivision scores almost as well.
        var selected = winner
        var requiredScore = 0.58
        if let bpm, time - confirmedAt < Self.expiry {
            let current = Int(bpm.rounded())
            if abs(current - winner) > 4 && votes[current] >= 0.92 * votes[winner] {
                selected = current
            }
            if abs(current - selected) <= 4 { requiredScore = 0.48 }
        }
        guard votes[selected] >= possible * requiredScore,
              newestSupport[selected] >= hits[hits.count - 1].weight * 0.45 else { return }
        bpm = Double(selected)
        confirmedAt = time
    }
}

/// A continuous visual oscillator. Tempo estimates change its velocity, never
/// its position, so acquiring or losing a beat cannot cause a color jump.
struct RhythmMotion {
    private var rate = 1.25
    private(set) var beats = 0.0

    var bpm: Double { rate * 60 }
    var phase: Double { beats - floor(beats) }

    mutating func advance(by dt: Double, bpm: Double?, onsetAge: Double) -> Double {
        let step = min(0.2, max(0, dt))
        var target = (bpm ?? 75) / 60
        if bpm != nil, onsetAge < 0.45 {
            let atHit = beats - onsetAge * target
            target += min(0.35, max(-0.35, (atHit.rounded() - atHit) * 0.9))
        }
        rate += (target - rate) * (1 - exp(-step / 0.55))
        beats += rate * step
        return beats
    }
}

extension AudioReading {
    var activeTempo: Double? { tempoEvidenceAge < TempoTracker.expiry ? bpm : nil }
}

struct BeatMonitor: Equatable {
    var detectedBPM: Int?
    var hitAge: Double
    var holding: Bool
    var clockBPM: Int
    var phase: Double

    init(reading: AudioReading?, motion: RhythmMotion) {
        detectedBPM = reading?.activeTempo.map { Int($0.rounded()) }
        hitAge = reading?.age ?? .infinity
        holding = (reading?.tempoEvidenceAge ?? .infinity) > 1.2
        clockBPM = Int(motion.bpm.rounded())
        phase = motion.phase
    }

    var hitLight: Double { max(0, 1 - hitAge / 0.16) }
}
