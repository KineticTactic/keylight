import Accelerate
import CoreMedia
import ScreenCaptureKit

// SCStream delivers both outputs on this serial queue. Reading a snapshot only
// holds the lock for a struct copy, never while processing sample buffers.
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "Keylight.capture")
    private let lock = NSLock()
    private var signals = Signals()
    private var stream: SCStream?
    private var needsScreen = false
    private var needsAudio = false
    private var lastInput = 0.0
    private let spectrum = AudioSpectrum()
    // Called by the editor on the main thread. Analysis state belongs to the capture queue.
    private var requestedRoutes: [AudioRoute] = []
    private var appliedRoutes: [AudioRoute] = []
    private var requestedGain = 0.0
    func configure(_ routes: [AudioRoute], inputGainDB: Double = 0) {
        lock.withLock {
            requestedRoutes = routes
            requestedGain = inputGainDB
        }
    }
    var failed: ((String) -> Void)?

    func snapshot() -> Signals {
        lock.withLock {
            var value = signals
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - lastInput - 0.08)
            let fade = exp(-elapsed * 10)
            let sinceInput = max(0, ProcessInfo.processInfo.systemUptime - lastInput)
            if let quiet = value.quietDuration { value.quietDuration = quiet + elapsed }
            value.meter = value.meter.map { $0 * fade }
            value.audio = value.audio.mapValues {
                var reading = $0
                reading.levels = reading.levels.map { $0 * fade }
                reading.age += sinceInput
                reading.tempoEvidenceAge += sinceInput
                return reading
            }
            return value
        }
    }

    func start(screen: Bool, audio: Bool, displayID: CGDirectDisplayID?) async throws {
        needsScreen = screen
        needsAudio = audio
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw LightingError("Selected display is unavailable. Select another display.")
        }
        let apps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 128
        config.height = 80
        config.preservesAspectRatio = false
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 24)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = audio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        if screen { try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue) }
        if audio { try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if audio {
            lock.withLock {
                lastInput = ProcessInfo.processInfo.systemUptime
                signals.quietDuration = 0
            }
        }
        try await capture.startCapture()
        stream = capture
    }

    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failed?(error.localizedDescription)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen, needsScreen, let image = sampleBuffer.imageBuffer { sampleScreen(image) }
        if type == .audio, needsAudio { sampleAudio(sampleBuffer) }
    }

    func sampleScreen(_ image: CVPixelBuffer) {
        guard CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let raw = CVPixelBufferGetBaseAddress(image) else { return }
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
        let stride = CVPixelBufferGetBytesPerRow(image)
        let ptr = raw.assumingMemoryBound(to: UInt8.self)
        let colors = Board.keys.map { key -> RGB in
            let x = min(width - 1, Int((key.x + key.width / 2) * Double(width) / Board.width))
            let y = min(height - 1, Int((key.y + 0.5) * Double(height) / Board.height))
            var red = 0, green = 0, blue = 0, count = 0
            for row in max(0, y - 2)...min(height - 1, y + 2) {
                for col in max(0, x - 2)...min(width - 1, x + 2) {
                    let index = row * stride + col * 4
                    blue += Int(ptr[index]); green += Int(ptr[index + 1]); red += Int(ptr[index + 2]); count += 1
                }
            }
            let scale = Double(count * 255)
            return RGB(r: Double(red) / scale, g: Double(green) / scale, b: Double(blue) / scale)
        }
        lock.withLock { signals.screen = zip(signals.screen, colors).map { $0.mix($1, 0.65) } }
    }

    func sampleAudio(_ sample: CMSampleBuffer) {
        guard let format = sample.formatDescription?.audioStreamBasicDescription,
              format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 1,
              let block = sample.dataBuffer else { return }
        let size = CMBlockBufferGetDataLength(block)
        guard size >= 4, size % 4 == 0 else { return }
        var samples = [Float](repeating: 0, count: size / 4)
        let status = samples.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: bytes.baseAddress!)
        }
        guard status == noErr else { return }
        let (routes, gain) = lock.withLock { (requestedRoutes, requestedGain) }
        spectrum.inputGainDB = gain
        if appliedRoutes != routes {
            spectrum.configure(routes)
            appliedRoutes = routes
        }
        spectrum.ingest(samples, rate: format.mSampleRate)
        let levels = spectrum.readings
        let meter = spectrum.meter
        lock.withLock {
            signals.quietDuration = spectrum.quietDuration
            signals.audio = levels
            signals.meter = meter
            lastInput = ProcessInfo.processInfo.systemUptime
        }
    }
}
