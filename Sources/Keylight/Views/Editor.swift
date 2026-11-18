import SwiftUI

private enum WorkspacePage: String, CaseIterable {
    case live = "Live view", layers = "Edit layers"
}

struct Editor: View {
    @ObservedObject var studio: Studio
    @State private var page = WorkspacePage.live
    @State private var selectedLayer: UUID?
    @State private var section = LayerPage.appearance
    @State private var showingDevice = false
    @State private var showingGain = false
    @State private var renaming = false

    var body: some View {
        HStack(spacing: 0) {
            library.frame(width: 204).background(.ultraThinMaterial)
            Rectangle().fill(StudioStyle.line).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: page == .live ? 14 : 8) {
                            heading
                            pinnedKeyboard(availableHeight: geometry.size.height)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                if page == .live { live }
                                else {
                                    LayerInspector(studio: studio, selectedLayer: $selectedLayer, section: $section)
                                        .padding(16).background(StudioStyle.panel.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                                        .id(studio.selected)
                                }
                                if !studio.storageError.isEmpty { Text(studio.storageError).foregroundStyle(.orange) }
                                if !studio.captureStatus.isEmpty && studio.captureStatus != "Capture active" {
                                    Text(studio.captureStatus).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 524, maxWidth: .infinity)
        }
        .background(StudioStyle.desk.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(StudioStyle.lilac)
        .frame(minWidth: 760, minHeight: 550)
        .onChange(of: studio.selected) { _, _ in
            renaming = false
            selectedLayer = nil
            section = .appearance
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                KeylightMark()
                Text("Keylight").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-1.1)
            }.padding(.leading, 19).padding(.top, 34).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group("Music", scenes: factoryScenes("Music"))
                    group("Ambient", scenes: factoryScenes("Ambient"))
                    group("Screen", scenes: studio.scenes.filter { $0.factoryMode != nil && $0.inputLabel.contains("Screen") })
                    group("My modes", scenes: studio.scenes.filter { $0.factoryMode == nil })
                }.padding(.horizontal, 9).padding(.bottom, 12)
            }
            Divider()
            HStack(spacing: 9) {
                Image(systemName: "keyboard").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("URX Core75").font(.headline)
                    Text(studio.connected ? "Connected" : studio.connecting ? "Connecting…" : "Preview only")
                        .font(.caption).foregroundStyle(studio.connected ? .mint : .secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .padding(14).contentShape(Rectangle())
            .overlay {
                Button { showingDevice.toggle() } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Keyboard connection")
                    .popover(isPresented: $showingDevice) { connection }
            }
        }
    }

    private func factoryScenes(_ input: String) -> [LightingScene] {
        studio.scenes.filter { $0.factoryMode != nil && $0.inputLabel == input }
    }

    @ViewBuilder private func group(_ title: String, scenes: [LightingScene]) -> some View {
        if !scenes.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 9).padding(.bottom, 4)
                ForEach(scenes) { scene in
                    ModeRow(scene: scene, selected: studio.selected == scene.id) { studio.selected = scene.id }
                }
            }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Keyboard connection", systemImage: "keyboard").font(.headline)
            Picker("Transport", selection: $studio.connectionChoice) {
                ForEach(ConnectionChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(studio.connected || studio.connecting)
            Text(studio.outputStatus).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Button(studio.connected ? "Disconnect" : "Connect keyboard") {
                if studio.connected { studio.disconnect() } else { studio.connect() }
            }.disabled(studio.connecting)
        }.padding(18).frame(width: 295)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(WorkspacePage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item == .live ? "waveform.path" : "square.3.layers.3d")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(page == item ? .primary : .secondary)
                            .padding(.horizontal, 13).frame(height: 36)
                            .background {
                                if page == item { Capsule().fill(.white.opacity(0.14)).padding(3) }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.opticalGlass(in: Capsule())
            Spacer()
            Button { showingGain.toggle() } label: {
                Label(String(format: "Input gain  %+.0f dB", studio.inputGainDB), systemImage: "slider.horizontal.3")
                    .font(.callout.monospacedDigit())
            }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8)
            .opticalGlass(in: Capsule(), interactive: true)
            .help("Global input gain").accessibilityLabel("Input gain")
            .popover(isPresented: $showingGain) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Input gain").font(.headline)
                        Spacer()
                        Text(String(format: "%+.0f dB", studio.inputGainDB)).monospacedDigit()
                    }
                    Slider(value: $studio.inputGainDB, in: -12...24, step: 1).accessibilityLabel("Global input gain")
                    HStack {
                        Text("−12 dB"); Spacer()
                        Button("Reset") { studio.inputGainDB = 0 }; Spacer(); Text("+24 dB")
                    }.font(.caption)
                }.padding(16).frame(width: 255)
            }
            Toggle("Capture", isOn: $studio.captureEnabled).toggleStyle(.switch).controlSize(.small)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .opticalGlass(in: Capsule(), tint: studio.captureEnabled ? .mint.opacity(0.25) : nil)
        }.padding(.horizontal, 18).frame(height: 52)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if renaming {
                    TextField("Mode name", text: $studio.scene.name).onSubmit { renaming = false }
                } else {
                    Text(studio.scene.name.isEmpty ? "Untitled mode" : studio.scene.name)
                        .lineLimit(2).textSelection(.enabled)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Menu {
                    Button("Rename mode") { renaming = true }
                    Button("Duplicate mode") { studio.duplicate() }
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Mode actions")
            }
            .font(.system(size: page == .live ? 39 : 24, weight: .heavy)).tracking(page == .live ? -1.8 : -0.8)
            if page == .live, let mode = studio.scene.factoryMode {
                Text(mode.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pinnedKeyboard(availableHeight: CGFloat) -> some View {
        let editing = page == .layers && section == .keys
        let layer = studio.scene.layers.first { $0.id == selectedLayer } ?? studio.scene.layers[0]
        let keybedHeight = availableHeight * (page == .live ? 0.38 : 0.23)
        let width = min(740, max(260, keybedHeight * Board.width / Board.height + 28))
        return KeyboardPreview(colors: studio.frame, mask: editing ? layer.keys : nil, editable: editing) { id in
            guard let index = studio.scene.layers.firstIndex(where: { $0.id == layer.id }) else { return }
            var keys = studio.scene.layers[index].keys ?? []
            if keys.contains(id) { keys.remove(id) } else { keys.insert(id) }
            studio.scene.layers[index].keys = keys
        }
        .frame(maxWidth: width)
        .padding(.vertical, page == .live ? 12 : 6)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var live: some View {
        HStack(spacing: 11) {
            Button { studio.paused.toggle() } label: {
                Image(systemName: studio.paused ? "play.fill" : "pause.fill")
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).opticalGlass(in: Circle(), interactive: true)
                .help(studio.paused ? "Resume" : "Pause").accessibilityLabel(studio.paused ? "Resume" : "Pause")
            HStack(spacing: 10) {
                Label("Brightness", systemImage: "sun.max.fill").font(.callout.weight(.semibold))
                Slider(value: $studio.scene.brightness, in: 0...1)
                    .accessibilityLabel("Scene brightness").tint(.black)
                Text(studio.scene.brightness, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(.black).environment(\.colorScheme, .light)
            .padding(.horizontal, 16).frame(height: 49)
            .background(StudioStyle.citrus, in: RoundedRectangle(cornerRadius: 15))
        }
        if let i = studio.scene.layers.firstIndex(where: { $0.effect == .ensemble }) {
            ReactivitySlider(value: layerBinding(i, \.reactivity))
                .padding(.horizontal, 16).padding(.vertical, 10).tint(.black).foregroundStyle(.black)
                .environment(\.colorScheme, .light).background(StudioStyle.lilac, in: RoundedRectangle(cornerRadius: 14))
        }
        if let i = studio.scene.layers.firstIndex(where: { $0.effect == .bloom }) {
            let direction = layerBinding(i, \.echoDirection)
            EchoDirectionPicker(direction: Binding(get: { direction.wrappedValue ?? .outward },
                                                   set: { direction.wrappedValue = $0 }))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .opticalGlass(in: Capsule(), tint: .pink.opacity(0.23))
        }
        if let clock = studio.scene.layers.first(where: { $0.effect.followsTempo }) {
            TempoStatus(monitor: studio.beatMonitors[clock.id], paused: studio.paused,
                        capturing: studio.captureEnabled, cycleBeats: clock.cycleBeats)
        }
        if studio.usesCapture || studio.captureEnabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Input spectrum").font(.headline)
                    Spacer()
                    if studio.scene.layers.contains(where: { $0.effect.usesScreen }) {
                        Picker("Display", selection: $studio.displayID) {
                            Text("Main display").tag(nil as CGDirectDisplayID?)
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                Text(screen.localizedName).tag(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
                            }
                        }.fixedSize()
                    }
                    Text(studio.paused ? "Paused" : studio.captureEnabled ? "Capture on" : "Capture off")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SpectrumPlot(levels: studio.meter, band: nil)
            }
        }
    }

    private func layerBinding<T>(_ i: Int, _ key: WritableKeyPath<Layer, T>) -> Binding<T> {
        let item = studio.scene.layers[i]
        return Binding(get: { studio.scene.layers.first(where: { $0.id == item.id })?[keyPath: key] ?? item[keyPath: key] },
                       set: { value in
                           if let index = studio.scene.layers.firstIndex(where: { $0.id == item.id }) {
                               studio.scene.layers[index][keyPath: key] = value
                           }
                       })
    }
}
