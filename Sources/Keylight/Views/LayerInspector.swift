import SwiftUI

private extension Effect {
    var colorLabels: (String, String, String) {
        switch self {
        case .spectrum: return ("Left color", "Middle color", "Right color")
        case .ensemble: return ("Rim", "Center", "Number row")
        case .orbits: return ("First light", "Background", "Second light")
        default: return ("Color", "Middle color", "Second color")
        }
    }
}

enum LayerPage: String, CaseIterable {
    case appearance = "Appearance", audio = "Audio", keys = "Keys"

    var symbol: String {
        switch self {
        case .appearance: return "paintpalette"
        case .audio: return "waveform"
        case .keys: return "keyboard"
        }
    }
}

struct LayerInspector: View {
    @ObservedObject var studio: Studio
    @Binding var selectedLayer: UUID?
    @Binding var section: LayerPage
    @State private var zone = 0
    private var layerIndex: Int { studio.scene.layers.firstIndex { $0.id == selectedLayer } ?? 0 }
    private var layer: Layer { studio.scene.layers[layerIndex] }
    private func edit<T>(_ path: WritableKeyPath<Layer, T>) -> Binding<T> {
        Binding(get: { layer[keyPath: path] }, set: { studio.scene.layers[layerIndex][keyPath: path] = $0 })
    }
    private func tint(_ path: WritableKeyPath<Layer, RGB>) -> Binding<Color> {
        Binding(get: { layer[keyPath: path].displayColor }, set: { studio.scene.layers[layerIndex][keyPath: path] = RGB($0) })
    }
    private func move(_ offset: Int) {
        let index = layerIndex
        selectedLayer = layer.id
        studio.scene.layers.swapAt(index, index + offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            management
            sectionSelector
            switch section {
            case .appearance: appearance
            case .audio: audio
            case .keys: keySelection
            }
        }
        .onChange(of: layer.id) { _, _ in zone = 0 }
        .onChange(of: layer.effect) { _, _ in zone = 0 }
    }

    private var sectionSelector: some View {
        HStack(spacing: 0) {
            ForEach(LayerPage.allCases, id: \.self) { item in
                let active = section == item
                Button { section = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(active ? Color.black : Color.white.opacity(0.82))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 8).fill(StudioStyle.lilac).padding(3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .opticalGlass(in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .contain).accessibilityLabel("Layer settings")
    }

    private var management: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Layer stack").font(.headline)
                Text("Front to back").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 1) {
                    stackAction("Move layer up", symbol: "chevron.up", disabled: layerIndex == studio.scene.layers.count - 1) { move(1) }
                    stackAction("Move layer down", symbol: "chevron.down", disabled: layerIndex == 0) { move(-1) }
                    stackAction("Remove layer", symbol: "trash", disabled: studio.scene.layers.count == 1) {
                        let index = layerIndex
                        studio.scene.layers.remove(at: index)
                        selectedLayer = studio.scene.layers[min(index, studio.scene.layers.count - 1)].id
                    }
                }
                Menu {
                    ForEach(Effect.allCases, id: \.self) { effect in
                        Button(effect.rawValue) {
                            let new = effect == .hiHat ? Layer.numberRowHiHat : Layer(effect: effect)
                            studio.scene.layers.append(new)
                            selectedLayer = new.id
                        }
                    }
                } label: { Label("Add layer", systemImage: "plus") }
                    .fixedSize()
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(studio.scene.layers.reversed()) { item in
                            LayerStackRow(layer: item, selected: layer.id == item.id) { selectedLayer = item.id }
                                .id(item.id)
                        }
                    }
                }
                .scrollDisabled(studio.scene.layers.count <= 4)
                .frame(height: CGFloat(min(4, studio.scene.layers.count)) * LayerStackRow.height)
                .background(StudioStyle.desk, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(StudioStyle.line).allowsHitTesting(false) }
                .onAppear { proxy.scrollTo(layer.id) }
                .onChange(of: selectedLayer) { _, id in if let id { proxy.scrollTo(id) } }
                .onChange(of: layerIndex) { _, _ in proxy.scrollTo(layer.id) }
            }
        }
    }

    private func stackAction(_ title: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 27, height: 27).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled).accessibilityLabel(title).help(title)
    }

    @ViewBuilder private var appearance: some View {
        Picker("Effect", selection: edit(\.effect)) {
            ForEach(Effect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.fixedSize()
        HStack(spacing: 16) {
            if !layer.effect.usesScreen {
                ColorPicker(layer.effect.colorLabels.0,
                            selection: tint(\.color), supportsOpacity: false).fixedSize()
            }
            if layer.effect == .spectrum || layer.effect.usesMix {
                ColorPicker(layer.effect.colorLabels.1, selection: tint(\.middle), supportsOpacity: false).fixedSize()
            }
            if [.wave, .ripple, .spectrum, .aurora, .meteors, .embers, .tempo, .ensemble, .orbits, .towers, .bloom].contains(layer.effect) {
                ColorPicker(layer.effect.colorLabels.2,
                            selection: tint(\.secondary), supportsOpacity: false).fixedSize()
            }
            if layer.effect.hasMotion {
                Text("Speed")
                Slider(value: edit(\.speed), in: 0...2).accessibilityLabel("Motion speed")
            }
        }
        if layer.effect.followsTempo {
            Picker("Beats per cycle", selection: Binding(get: { layer.cycleBeats },
                   set: { studio.scene.layers[layerIndex].beatsPerWave = $0 })) {
                ForEach([2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
        }
        HStack {
            Text("Opacity")
            Slider(value: edit(\.opacity), in: 0...1).accessibilityLabel("Layer opacity")
            Text(layer.opacity, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 42)
        }
        if layer.effect == .bloom {
            EchoDirectionPicker(direction: Binding(get: { layer.echoDirection ?? .outward },
                set: { studio.scene.layers[layerIndex].echoDirection = $0 }))
        }
        if layer.effect == .ensemble { ReactivitySlider(value: edit(\.reactivity)) }
    }

    @ViewBuilder private var audio: some View {
        SpectrumPlot(levels: studio.meter, band: layer.respondsToAudio ? layer.frequencyBands[min(zone, layer.frequencyBands.count - 1)] : nil)
        Toggle("Silence color", isOn: edit(\.usesSilenceColor))
        .toggleStyle(.switch)
        if layer.usesSilenceColor {
            HStack {
                ColorPicker("Resting color", selection: Binding(get: { (layer.silenceColor ?? layer.color).displayColor },
                    set: { studio.scene.layers[layerIndex].silenceColor = RGB($0) }), supportsOpacity: false)
                Spacer()
                Text("Fades in after 1.5 s of silence.").font(.caption).foregroundStyle(.secondary)
            }
        }
        SpectrumPanel(layer: Binding(get: { layer }, set: { studio.scene.layers[layerIndex] = $0 }), zone: $zone)
            .id(layer.id)
        if layer.respondsToAudio {
            HStack {
                Text(layer.effect.followsTempo ? "Beat sensitivity" : "Layer gain")
                Slider(value: edit(\.audio.gain), in: 0...8, step: 0.05).accessibilityLabel(layer.effect.followsTempo ? "Beat sensitivity" : "Layer gain")
                Text(String(format: "%.2f×", layer.audio.gain)).monospacedDigit().frame(width: 54)
            }
        }
        if layer.effect == .drum || layer.effect == .hiHat || layer.effect == .bloom {
            HStack {
                Text("Hit fade")
                Slider(value: edit(\.audio.fade), in: 0.06...0.8, step: 0.01).accessibilityLabel("Hit fade")
                Text("\(Int((layer.audio.fade * 1000).rounded())) ms").monospacedDigit().frame(width: 54)
            }
        }
        if layer.effect.usesMix {
            HStack {
                Text("Mix smoothing")
                Slider(value: Binding(get: { layer.mixSmoothing },
                       set: { studio.scene.layers[layerIndex].audio.smoothing = $0 }), in: 0.4...3, step: 0.1)
                    .accessibilityLabel("Mix smoothing")
                Text(String(format: "%.1f s", layer.mixSmoothing)).monospacedDigit().frame(width: 54)
            }
        }
        if layer.effect.usesBands {
            HStack {
                Text("Smoothing")
                Slider(value: edit(\.audio.smoothing), in: 0...0.6, step: 0.01).accessibilityLabel("Band smoothing")
                Text(layer.audio.smoothing == 0 ? "Off" : "\(Int((layer.audio.smoothing * 1000).rounded())) ms")
                    .monospacedDigit().frame(width: 54)
            }

        }
    }

    @ViewBuilder private var keySelection: some View {
        HStack {
            Text(layer.keys.map { "\($0.count) keys selected" } ?? "All keys").font(.headline)

            Spacer()
            Menu("Select keys") {
                Button("All keys") { studio.scene.layers[layerIndex].keys = nil }
                Button("No keys") { studio.scene.layers[layerIndex].keys = [] }
                Button("Perimeter") { studio.scene.layers[layerIndex].keys = Board.perimeter }
                Button("Number row (1–0)") { studio.scene.layers[layerIndex].keys = Board.numberRow }
                Button("Interior") { studio.scene.layers[layerIndex].keys = Board.interior }
            }.fixedSize()
        }
        Text(layer.keys == nil ? "Click a key to start a custom selection." : "Click keys to add or remove them from this layer.")
            .foregroundStyle(.secondary)

    }
}
