import Cocoa
import SwiftUI

/// Manages the native macOS Studio & Settings window for Palle.
/// Styled according to modern macOS Human Interface Guidelines (translucent vibrancy, unified toolbar).
public final class StudioWindowManager: NSObject, NSWindowDelegate {
    public static let shared = StudioWindowManager()

    private var windowController: NSWindowController?

    private override init() {
        super.init()
    }

    /// Presents the Palle Studio window, bringing it to the key front.
    public func show() {
        DispatchQueue.main.async {
            if let controller = self.windowController, let window = controller.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let rootView = StudioView()
            let hostingController = NSHostingController(rootView: rootView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.center()
            window.minSize = NSSize(width: 860, height: 560)
            window.title = "Palle Studio"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.setFrameAutosaveName("PalleStudioWindow")
            window.delegate = self
            window.contentViewController = hostingController

            let controller = NSWindowController(window: window)
            self.windowController = controller

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Toggles visibility of the Studio window
    public func toggle() {
        if let window = windowController?.window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    /// Closes the Studio window while preserving live wallpaper execution
    public func hide() {
        windowController?.window?.orderOut(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        // Window remains in memory for instant subsequent presentations
    }
}
