import SwiftUI

struct CalibrationSheet: View {
    @ObservedObject var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ColorCalibration
    @State private var target = CalibrationTarget.essentials[0]
    @State private var refining = false

    init(studio: Studio) {
        self.studio = studio
        _draft = State(initialValue: studio.calibration)
    }

    private var targets: [Int] {
        refining ? CalibrationTarget.refinements : CalibrationTarget.essentials
    }
    private var reference: RGB { CalibrationTarget.color(target) }
    private var output: RGB { draft.output(for: target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Calibrate keyboard colors").font(.title2.bold())
                Text("Match the hue of the lit keys to the screen swatch. Start with white. If it looks cyan, lower green and blue until the keys look neutral.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker("Color set", selection: Binding(get: { refining }, set: { refining = $0; target = targets[0] })) {
                Text("Essentials · 7").tag(false)
                Text("Fine tuning · 19").tag(true)
            }.pickerStyle(.segmented)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10), alignment: .leading, spacing: 5) {
                ForEach(targets, id: \.self) { index in
                    Button { target = index } label: {
                        RoundedRectangle(cornerRadius: 5).fill(CalibrationTarget.color(index).displayColor)
                            .frame(height: 22)
                            .padding(3)
                            .overlay { if index == target { RoundedRectangle(cornerRadius: 7).stroke(.primary, lineWidth: 2) } }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .help(CalibrationTarget.names[index]).accessibilityLabel(CalibrationTarget.names[index])
                    .accessibilityAddTraits(index == target ? .isSelected : [])
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 12).fill(reference.displayColor)
                        .frame(height: 99)
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.2)) }
                    Text(CalibrationTarget.names[target]).font(.headline)
                    Text(reference.bytes.map { String(format: "%02X", $0) }.joined().uppercased())
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .accessibilityLabel("Target hex color")
                }.frame(width: 132)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Keyboard output").font(.headline)
                    channel("Red", \.r, .red)
                    channel("Green", \.g, .green)
                    channel("Blue", \.b, .blue)
                    Button("Reset this color") { draft.matches.removeValue(forKey: target) }
                        .buttonStyle(.link).disabled(draft.matches[target] == nil)
                }
            }
            if !studio.connected {
                HStack {
                    Text(studio.outputStatus).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(studio.connecting ? "Connecting…" : "Connect keyboard") { studio.connect() }
                        .disabled(studio.connecting)
                }
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Back") { move(-1) }.disabled(target == CalibrationTarget.essentials.first)
                if target != CalibrationTarget.refinements.last {
                    Button(target == CalibrationTarget.essentials.last ? "Fine tune" : "Next") { move(1) }
                }
                Button("Apply to all modes") {
                    draft.enabled = true
                    studio.calibration = draft
                    studio.save()
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 550).background(StudioStyle.desk)
        .onAppear { studio.calibrationPatch = output }
        .onChange(of: output) { _, newValue in studio.calibrationPatch = newValue }
        .onDisappear { studio.calibrationPatch = nil }
    }

    private func move(_ direction: Int) {
        let all = CalibrationTarget.essentials + CalibrationTarget.refinements
        guard let index = all.firstIndex(of: target), all.indices.contains(index + direction) else { return }
        let next = all[index + direction]
        refining = CalibrationTarget.refinements.contains(next)
        target = next
    }

    private func channel(_ name: String, _ key: WritableKeyPath<RGB, Double>, _ tint: Color) -> some View {
        let value = Binding<Double>(
            get: { (output[keyPath: key] * 255).rounded() },
            set: { raw in
                var match = output
                match[keyPath: key] = raw.rounded() / 255
                draft.matches[target] = match
            }
        )
        return HStack(spacing: 8) {
            Text(name).frame(width: 40, alignment: .leading)
            Slider(value: value, in: 0...255, step: 1).tint(tint).accessibilityLabel("\(name) output")
            Text("\(Int(value.wrappedValue))").monospacedDigit().frame(width: 25, alignment: .trailing)
            Stepper("\(name) output", value: value, in: 0...255, step: 1).labelsHidden()
        }
    }
}
