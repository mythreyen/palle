import Cocoa
import CoreGraphics
import IOKit.ps

/// Monitors desktop occlusion, macOS Low Power Mode, and screen sleep state so the
/// wallpaper consumes 0% GPU when hidden behind maximized apps or when the display sleeps.
public final class PowerAndOcclusionMonitor {

    public var onPauseStateChanged: ((Bool, Int) -> Void)?
    private var timer: Timer?
    private var isScreenAsleep: Bool = false

    public init() {
        setupNotifications()
        startPolling()
    }

    private func setupNotifications() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreenSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(evaluatePowerAndVisibility),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    private func startPolling() {
        // Poll every 1.0s to check window occlusion with virtually zero CPU overhead
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluatePowerAndVisibility()
        }
    }

    @objc private func handleScreenSleep() {
        isScreenAsleep = true
        evaluatePowerAndVisibility()
    }

    @objc private func handleScreenWake() {
        isScreenAsleep = false
        evaluatePowerAndVisibility()
    }

    @objc public func evaluatePowerAndVisibility() {
        if isScreenAsleep {
            onPauseStateChanged?(true, 0)
            return
        }

        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let targetFPS = isLowPower ? 24 : WallpaperConfig.shared.preferredFPS

        if WallpaperConfig.shared.pauseWhenOccluded && isDesktopMostlyOccluded() {
            onPauseStateChanged?(true, targetFPS)
        } else {
            onPauseStateChanged?(false, targetFPS)
        }
    }

    /// Inspects on-screen windows above the desktop layer. If any single standard window covers
    /// >= 92% of the main screen's visible frame, we pause Metal rendering automatically.
    private func isDesktopMostlyOccluded() -> Bool {
        guard let mainScreen = NSScreen.main, let primary = NSScreen.screens.first else { return false }
        let screenArea = mainScreen.frame.width * mainScreen.frame.height
        guard screenArea > 0 else { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = primary.frame.height

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0, // Standard application window layer
                  let alpha = entry[kCGWindowAlpha as String] as? CGFloat,
                  alpha > 0.9,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"] else {
                continue
            }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            // Convert CoreGraphics top-left to Cocoa bottom-left coordinate space
            let cocoaY = primaryHeight - (cgY + h)
            let rect = CGRect(x: cgX, y: cocoaY, width: w, height: h)

            let intersection = rect.intersection(mainScreen.frame)
            let coveredArea = max(0, intersection.width) * max(0, intersection.height)

            if (coveredArea / screenArea) >= 0.92 {
                return true
            }
        }
        return false
    }
}
