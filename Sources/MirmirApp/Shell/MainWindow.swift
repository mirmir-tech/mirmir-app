import AppKit
import MirmirKit
import SwiftUI

/// Brings the main window forward. Mirmir is a menu bar agent: macOS does not
/// activate it on launch or when its panel opens a window, so without this the
/// window opens behind other apps, or is taken off screen moments after launch.
@MainActor
enum MainWindow {
    static func show(_ section: SidebarSection? = nil, model: AppModel, openWindow: OpenWindowAction) {
        if let section { model.section = section }
        closeMenuBarPanel()
        openWindow(id: WindowID.main)
        NSApp.activate()
        // A closed window is created by openWindow on the next pass.
        DispatchQueue.main.async { front() }
    }

    /// Opens the main window from outside a view, such as the app delegate:
    /// captured from the menu bar label, which exists for the app's lifetime.
    static var opener: OpenWindowAction?

    /// Shows the main window when the app is opened again (Finder, Dock,
    /// `open`), creating it when it was closed; `front` alone finds no window
    /// then.
    static func reopen() {
        if main == nil, let opener {
            opener(id: WindowID.main)
            // The window exists only after this pass.
            DispatchQueue.main.async { front() }
        } else {
            front()
        }
    }

    /// Activates the app and orders the main window in front of other apps.
    static func front() {
        NSApp.activate()
        guard let window = main else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    static var main: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }
    }

    /// The `.window` style panel stays open over the main window otherwise.
    static func closeMenuBarPanel() {
        for window in NSApp.windows where window.isVisible && window is NSPanel && window.identifier == nil {
            window.orderOut(nil)
        }
    }
}
