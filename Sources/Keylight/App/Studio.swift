import AppKit
import Combine

struct Library: Codable, Equatable {
    var scenes: [LightingScene]
    var selected: UUID
    var inputGainDB: Double?
    var calibration: ColorCalibration?
}

@MainActor
final class Studio: ObservableObject {
    @Published var scenes: [LightingScene] { didSet { scheduleSave() } }
    @Published var selected: UUID { didSet { scheduleSave() } }
    @Published var inputGainDB: Double { didSet { scheduleSave() } }
    @Published var calibration: ColorCalibration {
        didSet { outputLUT = ColorLUT(calibration); scheduleSave() }
    }
    var calibrationPatch: RGB?
    private var outputLUT: ColorLUT
    private var lastOutput: [RGB] = []
    @Published var frame = Array(repeating: RGB.black, count: Board.keys.count)
    @Published var beatMonitors: [UUID: BeatMonitor] = [:]
    @Published var meter = SpectrumMeter.silent
    @Published var paused = false
    @Published var connected = false
    @Published var connectionChoice = ConnectionChoice.automatic
    @Published var connecting = false
    @Published var outputStatus = "Preview only"
    @Published var captureStatus = ""
    @Published var captureEnabled = false
    @Published var displayID: CGDirectDisplayID?
    @Published var storageError = ""

    private let keyboard = Keyboard()
    private let usb = DispatchQueue(label: "Keylight.USB", qos: .userInitiated)
    private var busy = false
    private var epoch = 0
    private var silence = SilenceFade()
    private var bandFilter = BandSmoothing()
    private var rhythmClocks: [UUID: RhythmMotion] = [:]
    private var rhythmSceneID: UUID?
    private var elapsed = 0.0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var minecraftInput: MinecraftInput?
    private var capture: Capture?
    private var captureTask: Task<Void, Never>?
    private var captureKey = ""
    private var timer: AnyCancellable?
    private var saveTask: Task<Void, Never>?
    private let file: URL
    private var dirty = false

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keylight/Scenes.json")
        var library = Library.initial()
        var updatedCatalog = false
        var readError = ""
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                let saved = try JSONDecoder().decode(Library.self, from: Data(contentsOf: self.file))
                guard !saved.scenes.isEmpty, saved.scenes.allSatisfy({ !$0.layers.isEmpty }) else {
                    throw LightingError("The file contains an empty scene library or layer list.")
                }
                library = saved
                library.updateCatalog()
                updatedCatalog = library != saved
            } catch { readError = "Could not load Scenes.json. \(error.localizedDescription)" }
        }
        let profile = library.calibration ?? ColorCalibration()
        calibration = profile
        outputLUT = ColorLUT(profile)
        inputGainDB = min(24, max(-12, library.inputGainDB ?? 0))
        scenes = library.scenes
        selected = library.scenes.contains { $0.id == library.selected } ? library.selected : library.scenes[0].id
        storageError = readError
        if updatedCatalog {
            dirty = true
            save()
        }
        frame = EffectEngine.render(scene, time: 0, signals: Signals())
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    var scene: LightingScene {
        get { scenes.first { $0.id == selected } ?? scenes[0] }
        set {
            guard let index = scenes.firstIndex(where: { $0.id == selected }) else { return }
            scenes[index] = newValue
        }
    }

    func duplicate() {
        var copy = scene
        copy.id = UUID()
        copy.name = "\(copy.name) copy"
        scenes.append(copy)
        selected = copy.id
    }

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { save() }
        }
    }

    func save() {
        guard dirty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Library(scenes: scenes, selected: selected, inputGainDB: inputGainDB == 0 ? nil : inputGainDB,
                                                  calibration: calibration.matches.isEmpty ? nil : calibration))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Preserve the original if an existing library could not be decoded.
            if storageError.hasPrefix("Could not load"), FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("Scenes-\(UUID()).bak"))
            }
            try data.write(to: file, options: .atomic)
            storageError = ""
            dirty = false
        } catch { storageError = "Saving scenes failed. \(error.localizedDescription)" }
    }

    func connect() {
        guard !connected, !connecting else { return }
        connecting = true
        outputStatus = "Connecting…"
        let generation = epoch
        let choice = connectionChoice
        usb.async { [keyboard] in
            let result = Result { try keyboard.connect(choice); return keyboard.backend }
            DispatchQueue.main.async {
                guard generation == self.epoch else { return }
                self.connecting = false
                switch result {
                case .success(let backend): self.connected = true; self.outputStatus = backend
                case .failure(let error): self.outputStatus = error.localizedDescription
                }
            }
        }
    }

    func disconnect() {
        epoch += 1
        lastOutput = []
        connected = false
        connecting = false
        outputStatus = "Preview only"
        let generation = epoch
        usb.async { [keyboard] in
            do { try keyboard.disconnect() }
            catch {
                DispatchQueue.main.async {
                    guard generation == self.epoch else { return }
                    self.outputStatus = "Disconnected. Lighting restoration failed. " + error.localizedDescription
                }
            }
        }
    }

    func finish() {
        timer?.cancel()
        minecraftInput = nil
        save()
        epoch += 1
        usb.sync { keyboard.close() }
    }

    var usesCapture: Bool { scene.layers.contains { $0.effect.usesScreen || $0.respondsToAudio || $0.usesSilenceColor } }

    private func updateCapture() {
        let enabled = captureEnabled && !paused
        let screen = enabled && scene.layers.contains { $0.effect.usesScreen }
        let audio = enabled // The live spectrum also works without an audio-driven layer.
        let minecraft = screen && scene.layers.contains { $0.effect == .minecraft }
        let next = (screen || audio) ? "\(screen)/\(audio)/\(minecraft)/\(displayID ?? CGMainDisplayID())" : ""
        guard captureKey != next else { return }
        captureKey = next
        minecraftInput = nil
        bandFilter = BandSmoothing()
        silence = SilenceFade()
        let old = capture
        capture = nil
        let priorTask = captureTask
        priorTask?.cancel()
        captureStatus = next.isEmpty ? "" : "Starting capture…"
        let selectedDisplay = displayID
        captureTask = Task { [self] in
            await priorTask?.value
            await old?.stop()
            guard !Task.isCancelled, !next.isEmpty else { return }
            let source = Capture()
            source.configure(scene.layers.filter(\.respondsToAudio).map(AudioRoute.init), inputGainDB: inputGainDB)
            source.failed = { [weak self, weak source] message in
                DispatchQueue.main.async { [weak self, weak source] in
                    guard let self, let source, self.capture === source else { return }
                    self.captureEnabled = false
                    self.captureStatus = message
                }
            }
            do {
                try await source.start(screen: screen, audio: audio, displayID: selectedDisplay)
                if Task.isCancelled { await source.stop(); return }
                capture = source
                captureStatus = "Capture active"
                if minecraft {
                    do { minecraftInput = try MinecraftInput() }
                    catch { captureStatus = "Screen sync active. Minecraft events unavailable on port \(MinecraftInput.port). \(error.localizedDescription)" }
                }
            } catch {
                guard !Task.isCancelled else { return }
                captureKey = ""
                captureEnabled = false
                captureStatus = "Capture unavailable. \(error.localizedDescription)"
            }
        }
    }

    private func tick() {
        updateCapture()
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTick = now }
        guard !paused else {
            if !beatMonitors.isEmpty { beatMonitors = [:] }
            if meter != SpectrumMeter.silent { meter = SpectrumMeter.silent }
            sendOutput()
            return
        }
        let delta = now - lastTick
        elapsed += min(delta, 0.2)
        var signals = capture?.snapshot() ?? Signals()
        if let minecraftInput { signals.minecraft = minecraftInput.snapshot(at: now, outputReady: !connected || !busy) }
        signals.silenceBlend = silence.update(quietDuration: signals.quietDuration, delta: delta)
        if rhythmSceneID != selected {
            rhythmClocks.removeAll()
            rhythmSceneID = selected
        }
        var monitors: [UUID: BeatMonitor] = [:]
        let tempoLayers = scene.layers.filter { $0.effect.followsTempo }
        rhythmClocks = rhythmClocks.filter { id, _ in tempoLayers.contains { $0.id == id } }
        for layer in tempoLayers {
            let reading = signals.audio[layer.id]
            let age = reading?.age ?? .infinity
            let bpm = reading?.activeTempo
            var motion = rhythmClocks[layer.id] ?? RhythmMotion()
            signals.rhythmBeats[layer.id] = motion.advance(by: delta, bpm: bpm, onsetAge: age)
            rhythmClocks[layer.id] = motion
            monitors[layer.id] = BeatMonitor(reading: reading, motion: motion)
        }
        if monitors != beatMonitors { beatMonitors = monitors }
        capture?.configure(scene.layers.filter(\.respondsToAudio).map(AudioRoute.init), inputGainDB: inputGainDB)
        if meter != signals.meter { meter = signals.meter }
        let levels = bandFilter.update(scene: scene, audio: signals.audio, delta: delta)
        let rendered = EffectEngine.render(scene, time: elapsed, signals: signals, smoothedBands: levels)
        if rendered != frame { frame = rendered }
        sendOutput()
    }

    func physicalFrame() -> [RGB] {
        if let calibrationPatch { return Array(repeating: calibrationPatch, count: frame.count) }
        return outputLUT.apply(to: frame)
    }

    private func sendOutput() {
        guard connected, !busy else { return }
        let rendered = physicalFrame()
        guard rendered != lastOutput else { return }
        lastOutput = rendered
        busy = true
        let generation = epoch
        usb.async { [keyboard] in
            let result = Result { try keyboard.display(rendered) }
            DispatchQueue.main.async {
                self.busy = false
                guard generation == self.epoch else { return }
                if case .failure(let error) = result {
                    self.disconnect()
                    self.outputStatus = error.localizedDescription
                }
            }
        }
    }
}
