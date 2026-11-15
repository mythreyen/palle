import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktopController: DesktopWindowController!
    private var menuBarController: MenuBarController!
    private var powerMonitor: PowerAndOcclusionMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a background/Menu-Bar agent (no Dock icon clutter)
        NSApp.setActivationPolicy(.accessory)

        desktopController = DesktopWindowController()
        menuBarController = MenuBarController(windowController: desktopController)
        powerMonitor = PowerAndOcclusionMonitor()

        powerMonitor.onPauseStateChanged = { [weak self] shouldPause, targetFPS in
            self?.desktopController.setPaused(shouldPause, targetFPS: targetFPS)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
