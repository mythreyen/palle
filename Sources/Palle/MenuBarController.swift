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

        let studioItem = NSMenuItem(title: "🎛 Open Palle Studio...", action: #selector(openStudio), keyEquivalent: ",")
        studioItem.target = self
        menu.addItem(studioItem)
        menu.addItem(NSMenuItem.separator())

        // Terminal Animations Selector
        let sceneHeader = NSMenuItem(title: "Terminal Animations", action: nil, keyEquivalent: "")
        sceneHeader.isEnabled = false
        menu.addItem(sceneHeader)

        for scene in SceneGeometry.allCases {
            var title = scene.displayName
            if scene == .asciiBounce && config.custom3DText != "MYTH" {
                title = "📼 Bouncing \"\(config.custom3DText)\""
            }
            let item = NSMenuItem(title: title, action: #selector(selectScene(_:)), keyEquivalent: "")
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

        let chooseTitle: String
        if config.isCustomMediaActive {
            let typeTag: String
            switch config.customMediaType {
            case .video: typeTag = "Video"
            case .gif: typeTag = "GIF"
            case .image: typeTag = "Image"
            case .none: typeTag = "Active"
            }
            chooseTitle = "📁 Change Wallpaper... (\(config.customMediaName ?? "Active") • \(typeTag))"
        } else {
            chooseTitle = "📁 Choose Custom Wallpaper (Image, Video, GIF)..."
        }

        let chooseItem = NSMenuItem(title: chooseTitle, action: #selector(chooseCustomMedia), keyEquivalent: "o")
        chooseItem.target = self
        chooseItem.state = config.isCustomMediaActive ? .on : .off
        menu.addItem(chooseItem)

        let textTitle = "✏️ Set 3D Hologram Text... (Current: \"\(config.custom3DText)\")"
        let textItem = NSMenuItem(title: textTitle, action: #selector(setCustom3DText), keyEquivalent: "t")
        textItem.target = self
        menu.addItem(textItem)

        // Play/Pause control for animated video/GIF loops
        if config.customMediaType == .video || config.customMediaType == .gif {
            let isPlaying = MediaPlaybackEngine.shared.isPlaying
            let playTitle = isPlaying ? "⏸ Pause Playback" : "▶️ Resume Playback"
            let playItem = NSMenuItem(title: playTitle, action: #selector(togglePlayback), keyEquivalent: "p")
            playItem.target = self
            menu.addItem(playItem)
        }

        let trueColorItem = NSMenuItem(
            title: "🎨 True Color Mode (Source Media RGB)",
            action: #selector(toggleTrueColor),
            keyEquivalent: ""
        )
        trueColorItem.target = self
        trueColorItem.state = config.useTrueColor ? .on : .off
        menu.addItem(trueColorItem)

        if config.isCustomMediaActive {
            let clearItem = NSMenuItem(
                title: "🗑️ Clear Custom Wallpaper (Back to 3D)",
                action: #selector(clearCustomMedia),
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

        for theme in ColorThemePreset.all {
            let item = NSMenuItem(title: theme.name, action: #selector(selectColorTheme(_:)), keyEquivalent: "")
            item.target = self
            item.tag = theme.id
            item.state = (config.selectedTheme == theme.id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Power & Smart Throttling Toggles
        let fpsHeader = NSMenuItem(title: "Hardware Frame Rate", action: nil, keyEquivalent: "")
        fpsHeader.isEnabled = false
        menu.addItem(fpsHeader)

        let fpsOptions: [(Int, String)] = [
            (60, "60 FPS (Ultra Smooth)"),
            (30, "30 FPS (Power Saver - Recommended)"),
            (24, "24 FPS (Cinematic Eco)"),
            (15, "15 FPS (Ultra Low Power)")
        ]
        for (fps, title) in fpsOptions {
            let item = NSMenuItem(title: title, action: #selector(selectFPS(_:)), keyEquivalent: "")
            item.target = self
            item.tag = fps
            item.state = (config.preferredFPS == fps) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

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

    @objc private func openStudio() {
        StudioWindowManager.shared.show()
    }

    @objc private func selectScene(_ sender: NSMenuItem) {
        if let selected = SceneGeometry(rawValue: Int32(sender.tag)) {
            WallpaperConfig.shared.scene = selected
            WallpaperConfig.shared.isCustomImageActive = false
            rebuildMenu()
        }
    }

    @objc private func chooseCustomMedia() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        CustomWallpaperManager.shared.promptForCustomMedia(device: device) { [weak self] success in
            if success {
                self?.rebuildMenu()
            }
        }
    }

    @objc private func chooseCustomImage() {
        chooseCustomMedia()
    }

    @objc private func setCustom3DText() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        CustomTextManager.shared.promptForCustomText(device: device) { [weak self] success in
            if success {
                self?.rebuildMenu()
            }
        }
    }

    @objc private func togglePlayback() {
        MediaPlaybackEngine.shared.togglePlayPause()
        rebuildMenu()
    }

    @objc private func toggleTrueColor() {
        WallpaperConfig.shared.useTrueColor.toggle()
        rebuildMenu()
    }

    @objc private func clearCustomMedia() {
        CustomWallpaperManager.shared.clearCustomWallpaper()
        rebuildMenu()
    }

    @objc private func clearCustomImage() {
        clearCustomMedia()
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
        WallpaperConfig.shared.applyTheme(id: sender.tag)
        rebuildMenu()
    }

    @objc private func selectFPS(_ sender: NSMenuItem) {
        WallpaperConfig.shared.preferredFPS = sender.tag
        WallpaperConfig.shared.notifySettingsChanged()
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
