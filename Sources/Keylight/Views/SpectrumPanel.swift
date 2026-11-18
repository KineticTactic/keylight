import SwiftUI

struct SpectrumPlot: View {
    let levels: [Double]
    let band: FrequencyBand?
    @State private var hoverX: CGFloat?
    private let accent = StudioStyle.lilac

    var body: some View {
        Canvas { ctx, size in
            let area = CGRect(x: 38, y: 10, width: size.width - 51, height: size.height - 32)
            func x(_ hz: Double) -> Double { area.minX + area.width * log(hz / 30) / log(20000 / 30.0) }
            func y(_ db: Double) -> Double { area.maxY - area.height * min(1, max(0, (db + 80) / 80)) }
            func label(_ text: String) -> Text {
                Text(text).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.75))
            }
            if let band {
                let selection = CGRect(x: x(band.low), y: area.minY, width: x(band.high) - x(band.low), height: area.height)
                ctx.fill(Path(selection), with: .color(accent.opacity(0.11)))
            }
            for db in [0, -20, -40, -60, -80] {
                let yy = y(Double(db))
                ctx.fill(Path(CGRect(x: area.minX, y: yy, width: area.width, height: 0.5)), with: .color(.white.opacity(0.23)))
                ctx.draw(label("\(db)"), at: CGPoint(x: area.minX - 6, y: yy), anchor: .trailing)
            }
            for (hz, name) in [(30.0, "30"), (100, "100"), (300, "300"), (1000, "1k"), (3000, "3k"), (10000, "10k"), (20000, "20k")] {
                let xx = x(hz)
                ctx.fill(Path(CGRect(x: xx, y: area.minY, width: 0.5, height: area.height)), with: .color(.white.opacity(0.13)))
                ctx.draw(label(name), at: CGPoint(x: xx, y: area.maxY + 11))
            }
            for (i, level) in levels.enumerated() {
                let edges = SpectrumMeter.edges
                let center = sqrt(edges[i] * edges[i + 1])
                let active = band.map { ($0.low...$0.high).contains(center) } ?? true
                let xx = x(edges[i]), yy = y(20 * log10(max(0.0001, level)))
                let rect = CGRect(x: xx + 0.7, y: yy, width: max(1, x(edges[i + 1]) - xx - 1.4), height: area.maxY - yy)
                let tint = Color(hue: 0.45 + 0.43 * Double(i) / Double(levels.count), saturation: 0.74, brightness: 1)
                let paint: GraphicsContext.Shading = active
                    ? .linearGradient(Gradient(colors: [tint, tint.opacity(0.40)]),
                                      startPoint: CGPoint(x: xx, y: yy), endPoint: CGPoint(x: xx, y: area.maxY))
                    : .color(.white.opacity(0.30))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: paint)
            }
            if let band {
                var line = Path()
                line.move(to: CGPoint(x: x(band.low), y: y(band.thresholdDB)))
                line.addLine(to: CGPoint(x: x(band.high), y: y(band.thresholdDB)))
                ctx.stroke(line, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let hoverX, area.minX...area.maxX ~= hoverX {
                let fraction = (hoverX - area.minX) / area.width
                let i = min(levels.count - 1, Int(fraction * Double(levels.count)))
                let hz = sqrt(SpectrumMeter.edges[i] * SpectrumMeter.edges[i + 1])
                let db = 20 * log10(max(0.0001, levels[i]))
                let readout = String(format: "%.0f Hz  %.1f dB", hz, db)
                let anchorX = min(area.maxX - 54, max(area.minX + 54, hoverX))
                ctx.fill(Path(CGRect(x: hoverX, y: area.minY, width: 1, height: area.height)), with: .color(.white.opacity(0.65)))
                ctx.fill(Path(roundedRect: CGRect(x: anchorX - 54, y: area.minY, width: 108, height: 17),
                              cornerRadius: 3), with: .color(.black.opacity(0.9)))
                ctx.draw(label(readout), at: CGPoint(x: anchorX, y: area.minY + 8))
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hoverX = point.x
            case .ended: hoverX = nil
            }
        }
        .frame(height: 132)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(StudioStyle.line) }
        .accessibilityLabel("Playback frequency spectrum, 30 hertz to 20 kilohertz")
        .accessibilityValue(levels.max().map { $0 < 0.0001 ? "Silent" : "Peak \(Int(20 * log10($0))) decibels" } ?? "Silent")
    }
}

struct SpectrumPanel: View {
    @Binding var layer: Layer
    @Binding var zone: Int
    private var index: Int { min(zone, layer.frequencyBands.count - 1) }
    private var band: FrequencyBand { layer.frequencyBands[index] }
    private var isPercussion: Bool { layer.effect == .drum || layer.effect == .hiHat || layer.effect.followsTempo || layer.effect == .bloom }

    private func binding(_ key: WritableKeyPath<FrequencyBand, Double>, limits: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { band[keyPath: key] }, set: { value in
            guard value.isFinite else { return }
            var bands = layer.frequencyBands
            bands[index][keyPath: key] = min(limits.upperBound, max(limits.lowerBound, value))
            layer.frequencyBands = bands
        })
    }

    private func frequency(_ name: String, _ key: WritableKeyPath<FrequencyBand, Double>, _ limits: ClosedRange<Double>) -> some View {
        let hz = binding(key, limits: limits)
        let logHz = Binding(get: { log10(hz.wrappedValue) }, set: { hz.wrappedValue = pow(10, $0).rounded() })
        return HStack {
            Text(name).frame(width: 85, alignment: .leading)
            Slider(value: logHz, in: log10(30)...log10(20000)).accessibilityLabel(name)
            TextField(name, value: hz, format: .number.precision(.fractionLength(0)).grouping(.never))
                .multilineTextAlignment(.trailing).frame(width: 64)
            Text("Hz").foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio response").font(.headline)
            if layer.effect == .towers {
                Picker("Tower band", selection: $zone) {
                    ForEach(Array(layer.frequencyBands.enumerated()), id: \.offset) { i, band in
                        Text("Tower \(i + 1)   ·   \(Int(band.low.rounded()))–\(Int(band.high.rounded())) Hz").tag(i)
                    }
                }.fixedSize()
            } else if layer.effect.usesBands {
                Picker("Keyboard zone", selection: $zone) {
                    ForEach(0..<4) { i in Text(["Left", "Mid-left", "Mid-right", "Right"][i]).tag(i) }
                }.pickerStyle(.segmented)
            }
            if !layer.effect.usesAudio {
                Toggle("Modulate layer brightness with audio", isOn: Binding(get: { layer.audioModulation == true },
                      set: { layer.audioModulation = $0 }))
            }
            if layer.respondsToAudio {
                frequency("Low cutoff", \.low, 30...(band.high - 1))
                frequency("High cutoff", \.high, (band.low + 1)...20000)
                HStack {
                    Text(isPercussion ? "Hit threshold" : "Level threshold").frame(width: 85, alignment: .leading)
                    let threshold = binding(\.thresholdDB, limits: -80...0)
                    Slider(value: threshold, in: -80...0, step: 0.5).accessibilityLabel("Threshold")
                    TextField("Threshold", value: threshold, format: .number.precision(.fractionLength(1)))
                        .multilineTextAlignment(.trailing).frame(width: 64)
                    Text("dB").foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                }
                if layer.effect.usesBands {
                    HStack {
                        Text("Zone gain").frame(width: 85, alignment: .leading)
                        let gain = binding(\.gain, limits: 0...8)
                        Slider(value: gain, in: 0...8, step: 0.05).accessibilityLabel("Zone gain")
                        TextField("Zone gain", value: gain, format: .number.precision(.fractionLength(2)))
                            .frame(width: 64).multilineTextAlignment(.trailing)
                        Text("×").foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                    }
                }
                HStack {
                    Text(isPercussion ? "Threshold measures the rise on each attack." : "Levels below the threshold fade out.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset band") {
                        var bands = layer.frequencyBands
                        bands[index] = FrequencyBand.defaults(for: layer.effect)[index]
                        layer.frequencyBands = bands
                    }.controlSize(.small)
                }
            }
        }
    }
}
