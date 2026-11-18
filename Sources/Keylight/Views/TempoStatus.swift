import SwiftUI

struct TempoStatus: View {
    let monitor: BeatMonitor?
    let paused: Bool
    let capturing: Bool
    let cycleBeats: Int

    private var status: String {
        if paused { return "Paused" }
        if !capturing { return "Enable Capture to sync." }
        if let monitor, let bpm = monitor.detectedBPM {
            return "\(monitor.holding ? "Holding " : "")\(bpm) BPM · \(cycleBeats) beats per cycle"
        }
        return (monitor?.hitAge ?? .infinity) < TempoTracker.expiry ? "Finding tempo…" : "Listening for hits…"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { Text(status); indicators }.fixedSize()
            VStack(alignment: .leading, spacing: 5) { Text(status); indicators }
        }
        .font(.callout.monospacedDigit())
    }

    private var indicators: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().strokeBorder(.secondary, lineWidth: 1)
                    .background(Circle().fill(.orange.opacity(paused || !capturing ? 0 : monitor?.hitLight ?? 0)))
                    .frame(width: 11, height: 11)
                Text("Detected hit")
            }
            .help("Lights on each attack accepted by the audio detector.")
            HStack(spacing: 5) {
                ZStack {
                    Circle().strokeBorder(.secondary, lineWidth: 1)
                    if let monitor, !paused {
                        Circle().fill(.mint).frame(width: 4, height: 4)
                            .offset(y: -5).rotationEffect(.degrees(monitor.phase * 360))
                    }
                }
                .frame(width: 14, height: 14)
                Text(paused || monitor == nil ? "Metronome —" : "Metronome \(monitor?.clockBPM ?? 75) BPM")
            }
            .help("One turn per beat of the lighting clock. The dot crosses the top on each tick.")
        }
        .font(.caption.monospacedDigit())
    }
}
