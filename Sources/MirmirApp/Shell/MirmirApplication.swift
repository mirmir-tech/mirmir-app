import AppKit
import MirmirKit
import SwiftUI

@main
struct MirmirApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Mirmir", id: WindowID.main) {
            RootView()
                .environment(delegate.model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { MirmirCommands(model: delegate.model) }

        MenuBarExtra {
            MenuBarPanel()
                .environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.model)
        }
    }
}

enum WindowID {
    static let main = "main"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var signalSources: [any DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill` or Ctrl-C would skip applicationWillTerminate and leave the
        // owned server running; route them through a normal quit.
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        // Run unbundled (`swift run`) the process would otherwise stay an
        // accessory without a Dock icon or key window.
        if Bundle.main.bundleIdentifier == nil { NSApp.setActivationPolicy(.regular) }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MirmirCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { show(.chat); model.chat.newConversation() }
                .keyboardShortcut("n")
        }
        CommandMenu("Go") {
            Button("Dashboard") { show(.overview) }.keyboardShortcut("1")
            Button("Models") { show(.models) }.keyboardShortcut("2")
            Button("Instances") { show(.instances) }.keyboardShortcut("3")
            Button("Chat") { show(.chat) }.keyboardShortcut("4")
            Button("Sessions") { show(.sessions) }.keyboardShortcut("5")
            Button("Logs") { show(.logs) }.keyboardShortcut("6")
        }
    }

    private func show(_ section: SidebarSection) {
        model.section = section
        openWindow(id: WindowID.main)
        NSApp.activate()
    }
}
