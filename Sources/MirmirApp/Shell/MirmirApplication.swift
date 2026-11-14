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
    /// Its chats are read in `start`, once an older copy has quit and
    /// saved its own; reading them earlier would save over those.
    let model = AppModel(loadsChatsNow: false)
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
        // One copy per user: every copy adds its own menu bar item and would
        // supervise its own server. The newest wins, so a fresh Xcode run
        // replaces one the debugger lost track of.
        let older = Self.otherInstances()
        older.forEach { $0.terminate() }
        Task {
            for _ in 0..<50 where older.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            model.start()
        }
        // Launched as an agent, the app is not activated by macOS, which then
        // takes the launch window off screen after a few seconds.
        DispatchQueue.main.async { MainWindow.front() }
    }

    private static func otherInstances() -> [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Chats that cannot be saved are not lost silently: the user can try
    /// again, quit anyway or keep the app open.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        while let failure = model.chat.saveNow() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Chats could not be saved"
            alert.informativeText = "\(failure.reason)\n\nQuitting now loses the changes made since the last successful save."
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: continue
            case .alertSecondButtonReturn: return .terminateNow
            default: return .terminateCancel
            }
        }
        // Saved chats that could not be read are never written over, so this
        // session's chats exist only in memory.
        if model.chat.hasUnsavedChanges {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "This session's chats are not saved"
            alert.informativeText = (model.chat.loadIssue?.message ?? "Saved chats could not be read.")
                + "\n\nQuitting now loses the chats and messages of this session."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    /// A menu bar agent (`LSUIElement`): no Dock icon or menu bar of its own.
    /// Closing the window leaves the menu bar item, which is the app; quit
    /// from its panel.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the running app again from Finder, Launchpad or `open` shows
    /// the main window, recreating it when it was closed. Without this an
    /// agent app has no window to bring back and nothing appears.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.reopen()
        return false
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
        MainWindow.show(section, model: model, openWindow: openWindow)
    }
}
