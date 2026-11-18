import SwiftUI

enum StudioStyle {
    static let desk = Color(red: 0.035, green: 0.035, blue: 0.055)
    static let panel = Color(red: 0.11, green: 0.115, blue: 0.16)
    static let lilac = Color(red: 0.84, green: 0.72, blue: 1)
    static let citrus = Color(red: 1, green: 0.84, blue: 0.32)
    static let line = Color.white.opacity(0.15)
}

struct KeylightMark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4) { n in
                RoundedRectangle(cornerRadius: 2)
                    .fill([Color(red: 0.98, green: 0.55, blue: 0.58), .orange, .mint, StudioStyle.lilac][n])
                    .frame(width: 5, height: [12.0, 20, 16, 25][n])
            }
        }.accessibilityHidden(true)
    }
}

struct ReactivitySlider: View {
    @Binding var value: Double
    var body: some View {
        HStack(spacing: 8) {
            Label("Reactivity", systemImage: "waveform")
            Slider(value: $value, in: 0.5...2, step: 0.05)
                .accessibilityLabel("Velvet Ensemble reactivity")
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.caption.monospacedDigit()).frame(width: 34)
        }
    }
}

struct EchoDirectionPicker: View {
    @Binding var direction: EchoDirection
    var body: some View {
        Picker("Wave direction", selection: $direction) {
            ForEach(EchoDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.fixedSize()
    }
}

extension View {
    @ViewBuilder func opticalGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            let surface = Glass.regular.tint(tint)
            glassEffect(interactive ? surface.interactive() : surface, in: shape)
        } else {
            background(.thinMaterial, in: shape)
                .background((tint ?? Color.clear).opacity(0.28), in: shape)
        }
    }
}
