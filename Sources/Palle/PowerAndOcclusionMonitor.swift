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

    /// Inspects on-screen windows above the desktop layer. If application windows cover >= 90%
    /// of the main screen (whether by a single window or tiled/split-screen windows),
    /// we pause Metal rendering automatically to achieve 0.0% GPU load.
    private func isDesktopMostlyOccluded() -> Bool {
        guard let mainScreen = NSScreen.main, let primary = NSScreen.screens.first else { return false }
        let screenFrame = mainScreen.frame
        let screenArea = screenFrame.width * screenFrame.height
        guard screenArea > 0 else { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = primary.frame.height
        var appWindowRects: [CGRect] = []

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0, // Standard application window layer
                  let alpha = entry[kCGWindowAlpha as String] as? CGFloat,
                  alpha > 0.85,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 50, h > 50 else {
                continue
            }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            // Convert CoreGraphics top-left to Cocoa bottom-left coordinate space
            let cocoaY = primaryHeight - (cgY + h)
            let rect = CGRect(x: cgX, y: cocoaY, width: w, height: h)

            let intersection = rect.intersection(screenFrame)
            guard !intersection.isNull && intersection.width > 0 && intersection.height > 0 else { continue }

            // Fast-path: single maximized window covering >= 90%
            let coveredArea = intersection.width * intersection.height
            if (coveredArea / screenArea) >= 0.90 {
                return true
            }

            appWindowRects.append(intersection)
        }

        guard !appWindowRects.isEmpty else { return false }

        // Multi-window coverage test: 8x8 probe grid (64 sample points) across the screen
        let cols = 8
        let rows = 8
        var coveredPoints = 0
        let stepX = screenFrame.width / CGFloat(cols)
        let stepY = screenFrame.height / CGFloat(rows)

        for col in 0..<cols {
            let px = screenFrame.minX + (CGFloat(col) + 0.5) * stepX
            for row in 0..<rows {
                let py = screenFrame.minY + (CGFloat(row) + 0.5) * stepY
                let point = CGPoint(x: px, y: py)

                for rect in appWindowRects {
                    if rect.contains(point) {
                        coveredPoints += 1
                        break
                    }
                }
            }
        }

        // If >= 90% (58 of 64) sample points are covered by windows, the desktop is occluded
        return (Double(coveredPoints) / Double(cols * rows)) >= 0.90
    }
}
