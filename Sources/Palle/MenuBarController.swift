import Cocoa
import simd

public final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem!
    private let windowController: DesktopWindowController

    public init(windowController: DesktopWindowController) {
        self.windowController = windowController
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "MYTH::3D"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let config = WallpaperConfig.shared

        let titleItem = NSMenuItem(title: "Palle — MYTH Edition", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // 3D Geometry Selector
        let sceneHeader = NSMenuItem(title: "3D Scene Geometry", action: nil, keyEquivalent: "")
        sceneHeader.isEnabled = false
        menu.addItem(sceneHeader)

        for scene in SceneGeometry.allCases {
            let item = NSMenuItem(title: scene.displayName, action: #selector(selectScene(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(scene.rawValue)
            item.state = (!config.isCustomImageActive && config.scene == scene) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Custom Wallpaper Section
        let customHeader = NSMenuItem(title: "Custom Wallpaper", action: nil, keyEquivalent: "")
        customHeader.isEnabled = false
        menu.addItem(customHeader)

        let chooseTitle = config.isCustomImageActive
            ? "📁 Change Custom Image... (\(config.customImageName ?? "Active"))"
            : "📁 Choose Custom Image Wallpaper..."
        let chooseItem = NSMenuItem(title: chooseTitle, action: #selector(chooseCustomImage), keyEquivalent: "o")
        chooseItem.target = self
        chooseItem.state = config.isCustomImageActive ? .on : .off
        menu.addItem(chooseItem)

        let trueColorItem = NSMenuItem(
            title: "🎨 True Color Mode (Source Photo RGB)",
            action: #selector(toggleTrueColor),
            keyEquivalent: ""
        )
        trueColorItem.target = self
        trueColorItem.state = config.useTrueColor ? .on : .off
        menu.addItem(trueColorItem)

        if config.isCustomImageActive {
            let clearItem = NSMenuItem(
                title: "🗑️ Clear Custom Wallpaper (Back to 3D)",
                action: #selector(clearCustomImage),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Character & Number Palette Selector
        let paletteHeader = NSMenuItem(title: "Character / Number Art Palette", action: nil, keyEquivalent: "")
        paletteHeader.isEnabled = false
        menu.addItem(paletteHeader)

        for (idx, palette) in CharacterPalette.allCases.enumerated() {
            let item = NSMenuItem(title: palette.displayName, action: #selector(selectPalette(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            item.state = (config.palette == palette) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // ASCII Detail & Resolution
        let detailHeader = NSMenuItem(title: "ASCII Detail & Resolution", action: nil, keyEquivalent: "")
        detailHeader.isEnabled = false
        menu.addItem(detailHeader)

        for preset in DetailResolution.allCases {
            let item = NSMenuItem(title: preset.displayName, action: #selector(selectResolution(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(preset.rawValue)
            item.state = (abs(config.fontSize - preset.rawValue) < 0.5) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Color Presets
        let colorHeader = NSMenuItem(title: "Color Theme", action: nil, keyEquivalent: "")
        colorHeader.isEnabled = false
        menu.addItem(colorHeader)

        let themes = [
            "Matrix Mint",
            "Amber CRT",
            "Cyber Cyan",
            "Monochrome Paper",
            "Holiday Evergreen",
            "Winter Frost",
            "Neon Sunset",
            "Mythic Amethyst & Gold",
            "Mythic Crimson Cyber"
        ]
        for (idx, name) in themes.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(selectColorTheme(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            item.state = (config.selectedTheme == idx) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Power & Smart Throttling Toggles
        let occlusionItem = NSMenuItem(
            title: "Smart Pause When Desktop Occluded",
            action: #selector(toggleOcclusionPause),
            keyEquivalent: ""
        )
        occlusionItem.target = self
        occlusionItem.state = config.pauseWhenOccluded ? .on : .off
        menu.addItem(occlusionItem)

        let parallaxItem = NSMenuItem(
            title: "Interactive Mouse Parallax",
            action: #selector(toggleMouseParallax),
            keyEquivalent: ""
        )
        parallaxItem.target = self
        parallaxItem.state = config.mouseParallaxEnabled ? .on : .off
        menu.addItem(parallaxItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Palle", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func selectScene(_ sender: NSMenuItem) {
        if let selected = SceneGeometry(rawValue: Int32(sender.tag)) {
            WallpaperConfig.shared.scene = selected
            WallpaperConfig.shared.isCustomImageActive = false
            rebuildMenu()
        }
    }

    @objc private func chooseCustomImage() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        CustomWallpaperManager.shared.promptForCustomImage(device: device) { [weak self] success in
            if success {
                self?.rebuildMenu()
            }
        }
    }

    @objc private func toggleTrueColor() {
        WallpaperConfig.shared.useTrueColor.toggle()
        rebuildMenu()
    }

    @objc private func clearCustomImage() {
        CustomWallpaperManager.shared.clearCustomWallpaper()
        rebuildMenu()
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        let all = CharacterPalette.allCases
        guard sender.tag >= 0 && sender.tag < all.count else { return }
        WallpaperConfig.shared.palette = all[sender.tag]
        windowController.refreshAtlas()
        rebuildMenu()
    }

    @objc private func selectResolution(_ sender: NSMenuItem) {
        let size = CGFloat(sender.tag)
        WallpaperConfig.shared.fontSize = size
        windowController.refreshAtlas()
        rebuildMenu()
    }

    @objc private func selectColorTheme(_ sender: NSMenuItem) {
        let config = WallpaperConfig.shared
        config.selectedTheme = sender.tag
        switch sender.tag {
        case 0: // Matrix Mint
            config.fgColor = SIMD4<Float>(0.15, 0.95, 0.65, 1.0)
            config.bgColor = SIMD4<Float>(0.03, 0.04, 0.06, 1.0)
        case 1: // Amber CRT
            config.fgColor = SIMD4<Float>(1.00, 0.72, 0.18, 1.0)
            config.bgColor = SIMD4<Float>(0.06, 0.04, 0.02, 1.0)
        case 2: // Cyber Cyan
            config.fgColor = SIMD4<Float>(0.20, 0.85, 1.00, 1.0)
            config.bgColor = SIMD4<Float>(0.02, 0.04, 0.09, 1.0)
        case 3: // Monochrome Paper
            config.fgColor = SIMD4<Float>(0.92, 0.94, 0.96, 1.0)
            config.bgColor = SIMD4<Float>(0.07, 0.07, 0.08, 1.0)
        case 4: // Holiday Evergreen (Vibrant Pine Green on Deep Crimson/Black)
            config.fgColor = SIMD4<Float>(0.22, 0.94, 0.48, 1.0)
            config.bgColor = SIMD4<Float>(0.12, 0.02, 0.04, 1.0)
        case 5: // Winter Frost (Glacial Ice Blue on Polar Midnight)
            config.fgColor = SIMD4<Float>(0.65, 0.92, 1.00, 1.0)
            config.bgColor = SIMD4<Float>(0.02, 0.05, 0.12, 1.0)
        case 6: // Neon Sunset (Synthwave Pink on Dark Violet)
            config.fgColor = SIMD4<Float>(1.00, 0.35, 0.75, 1.0)
            config.bgColor = SIMD4<Float>(0.08, 0.02, 0.12, 1.0)
        case 7: // Mythic Amethyst & Gold
            config.fgColor = SIMD4<Float>(1.00, 0.85, 0.25, 1.0)
            config.bgColor = SIMD4<Float>(0.07, 0.02, 0.12, 1.0)
        case 8: // Mythic Crimson Cyber
            config.fgColor = SIMD4<Float>(1.00, 0.18, 0.38, 1.0)
            config.bgColor = SIMD4<Float>(0.02, 0.04, 0.09, 1.0)
        default:
            break
        }
        rebuildMenu()
    }

    @objc private func toggleOcclusionPause() {
        WallpaperConfig.shared.pauseWhenOccluded.toggle()
        rebuildMenu()
    }

    @objc private func toggleMouseParallax() {
        WallpaperConfig.shared.mouseParallaxEnabled.toggle()
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
