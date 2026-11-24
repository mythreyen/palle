import Cocoa
import SwiftUI

/// Manages the native macOS Studio & Settings window for Palle.
/// Styled according to modern macOS Human Interface Guidelines (translucent vibrancy, unified toolbar).
public final class StudioWindowManager: NSObject, NSWindowDelegate {
    public static let shared = StudioWindowManager()

    public static let didShowWindowNotification = Notification.Name("PalleStudioWindowDidShow")
    public static let didHideWindowNotification = Notification.Name("PalleStudioWindowDidHide")

    private var windowController: NSWindowController?

    private override init() {
        super.init()
    }

    /// Presents the Palle Studio window, bringing it to the key front.
    public func show() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didShowWindowNotification, object: nil)

            if let controller = self.windowController, let window = controller.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let rootView = StudioView()
            let hostingController = NSHostingController(rootView: rootView)

            let initialW: CGFloat = 880
            let initialH: CGFloat = 600
            let minW: CGFloat = 780
            let minH: CGFloat = 520

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: initialW, height: initialH),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.minSize = NSSize(width: minW, height: minH)
            window.title = "Palle Studio"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.delegate = self
            window.contentViewController = hostingController

            // Responsive multi-display positioning & boundary clamp
            if !window.setFrameUsingName("PalleStudioWindow") {
                window.center()
            }
            if let screen = NSScreen.main {
                let vis = screen.visibleFrame
                var f = window.frame
                if f.width > vis.width { f.size.width = max(minW, vis.width - 40) }
                if f.height > vis.height { f.size.height = max(minH, vis.height - 40) }
                if f.maxY > vis.maxY { f.origin.y = vis.maxY - f.height }
                if f.minY < vis.minY { f.origin.y = vis.minY }
                if f.minX < vis.minX { f.origin.x = vis.minX }
                if f.maxX > vis.maxX { f.origin.x = vis.maxX - f.width }
                window.setFrame(f, display: false)
            }
            window.setFrameAutosaveName("PalleStudioWindow")

            let controller = NSWindowController(window: window)
            self.windowController = controller

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Toggles visibility of the Studio window
    public func toggle() {
        if let window = windowController?.window, window.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Closes the Studio window while preserving live wallpaper execution
    public func hide() {
        NotificationCenter.default.post(name: Self.didHideWindowNotification, object: nil)
        windowController?.window?.orderOut(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.didHideWindowNotification, object: nil)
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.didHideWindowNotification, object: nil)
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.didShowWindowNotification, object: nil)
    }
}
