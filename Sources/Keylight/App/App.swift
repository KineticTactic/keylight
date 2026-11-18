import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var studio = Studio()

    func applicationDidFinishLaunching(_ notification: Notification) {
        studio.connect()
    }

    func applicationWillTerminate(_ notification: Notification) { studio.finish() }
}

@main
struct KeylightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        let args = CommandLine.arguments
        if args.contains("--devices") || args.contains("--probe") || args.contains("--test-keys") {
            let board = Keyboard()
            let choice: ConnectionChoice = args.contains("--wireless") ? .receiver : (args.contains("--wired") ? .wired : .automatic)
            let devices = board.devices(choice)
            guard !devices.isEmpty else { print("No matching Core75 lighting interface (\(choice.rawValue))"); exit(1) }
            for (link, _) in devices {
                print(String(format: "URX Core75 · %@ · 36b0:%04x · HID ff60:0061", link.label, link.rawValue))
            }
            if args.contains("--probe") {
                do { try board.connect(choice, probeOnly: true); print("Verified lighting interface: \(board.backend)") }
                catch { print(error.localizedDescription); exit(1) }
            }
            if args.contains("--test-keys") {
                do { try board.testKeys(choice) } catch { print(error.localizedDescription); exit(1) }
            }
            exit(0)
        }
    }

    var body: some Scene {
        Window("Keylight", id: "studio") {
            Editor(studio: delegate.studio)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 750)
        MenuBarExtra("Keylight", systemImage: "keyboard") {
            KeylightMenu(studio: delegate.studio)
        }
    }
}

private struct KeylightMenu: View {
    @ObservedObject var studio: Studio
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Keylight") {
            openWindow(id: "studio")
            NSApp.activate(ignoringOtherApps: true)
        }
        Picker("Lighting mode", selection: $studio.selected) {
            ForEach(studio.scenes) { Text($0.name).tag($0.id) }
        }
        Button(studio.paused ? "Resume" : "Pause") { studio.paused.toggle() }
        Divider()
        Button("Quit Keylight") { NSApp.terminate(nil) }
    }
}
