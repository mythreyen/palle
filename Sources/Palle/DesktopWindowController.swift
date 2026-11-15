import Cocoa
import MetalKit

/// Manages one borderless, click-through `NSWindow` per connected `NSScreen`, positioned at
/// `kCGDesktopWindowLevelKey` so desktop icons and regular windows float naturally above it.
public final class DesktopWindowController {

    private var windows: [NSWindow] = []
    private var views: [MTKView] = []
    private var renderers: [ASCIIRenderer] = []

    public init() {
        rebuildDesktopWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenChange() {
        rebuildDesktopWindows()
    }

    public func rebuildDesktopWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        renderers.removeAll()

        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("[Palle] Metal is not supported on this Mac.")
            return
        }

        CustomWallpaperManager.shared.restoreSavedWallpaperIfAny(device: device)
        CustomTextManager.shared.restoreSavedTextIfAny(device: device)

        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))

        for screen in NSScreen.screens {
            let mtkView = MTKView(frame: screen.frame, device: device)
            mtkView.preferredFramesPerSecond = WallpaperConfig.shared.preferredFPS
            mtkView.enableSetNeedsDisplay = false
            mtkView.isPaused = false

            guard let renderer = ASCIIRenderer(mtkView: mtkView) else { continue }
            mtkView.delegate = renderer

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(screen.frame, display: true)
            window.level = NSWindow.Level(rawValue: desktopLevel)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.contentView = mtkView
            window.makeKeyAndOrderFront(nil)

            windows.append(window)
            views.append(mtkView)
            renderers.append(renderer)
        }
    }

    public func setPaused(_ paused: Bool, targetFPS: Int) {
        if paused {
            MediaPlaybackEngine.shared.pause()
        } else {
            MediaPlaybackEngine.shared.resume()
        }

        for view in views {
            if view.isPaused != paused {
                view.isPaused = paused
            }
            if targetFPS > 0 && view.preferredFramesPerSecond != targetFPS {
                view.preferredFramesPerSecond = targetFPS
            }
        }
    }

    public func refreshAtlas() {
        renderers.forEach { $0.rebuildFontAtlas() }
    }
}
