import Cocoa
import Metal
import SwiftUI
import UniformTypeIdentifiers

public enum StudioTab: String, CaseIterable, Identifiable {
    case scenes = "3D Scenes"
    case media = "Custom Media"
    case text3D = "3D Text"
    case appearance = "Appearance"
    case engine = "Engine & Display"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .scenes: return "cube.transparent"
        case .media: return "photo.stack"
        case .text3D: return "character.cursor.ibeam"
        case .appearance: return "paintpalette"
        case .engine: return "gauge.with.needle"
        }
    }
}

public struct StudioView: View {
    @ObservedObject private var config = WallpaperConfig.shared
    @State private var selectedTab: StudioTab = .scenes
    @State private var textInput: String = WallpaperConfig.shared.custom3DText
    @State private var isDropTargeted: Bool = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailContentView
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            textInput = config.custom3DText
        }
    }

    // MARK: - Sidebar
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Branding Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(simd4: config.fgColor), Color(simd4: config.fgColor).opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "terminal.fill")
                        .foregroundColor(.black)
                        .font(.system(size: 16, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("PALLE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                    Text("3D ASCII Engine")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 12)

            // Navigation List
            List(StudioTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
            .listStyle(.sidebar)

            Spacer()

            // Footer Status Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Desktop Engine Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text(activeStatusLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    private var activeStatusLabel: String {
        if config.isCustomMediaActive {
            return "Media: \(config.customMediaName ?? "Active")"
        } else {
            return "Scene: \(config.scene.displayName)"
        }
    }

    // MARK: - Detail Content
    @ViewBuilder
    private var detailContentView: some View {
        VStack(spacing: 0) {
            // Live ASCII Mini Viewport Header
            liveViewportCard
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .scenes:
                        scenesSection
                    case .media:
                        mediaSection
                    case .text3D:
                        text3DSection
                    case .appearance:
                        appearanceSection
                    case .engine:
                        engineSection
                    }
                }
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Live Viewport Header Card
    private var liveViewportCard: some View {
        HStack(spacing: 16) {
            // Mini 3D Metal Viewport
            ZStack {
                LiveASCIIPreviewView()
                    .frame(width: 220, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)

                // Corner live indicator
                VStack {
                    HStack {
                        Spacer()
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                    Spacer()
                }
            }
            .frame(width: 220, height: 110)

            // Live Telemetry Details
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(config.isCustomMediaActive ? (config.customMediaName ?? "Custom Media") : config.scene.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    if config.isCustomMediaActive {
                        Text(config.customMediaType.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(config.isCustomMediaActive ? "Custom Wallpaper Texture Stream" : config.scene.category)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    telemetryPill(icon: "speedometer", text: "\(config.preferredFPS) FPS")
                    telemetryPill(icon: "textformat.size", text: "\(Int(config.fontSize))pt Detail")
                    telemetryPill(
                        icon: "paintpalette.fill",
                        text: ColorThemePreset.all.first(where: { $0.id == config.selectedTheme })?.name ?? "Custom"
                    )
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func telemetryPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(NSColor.controlColor).opacity(0.6))
        .clipShape(Capsule())
    }

    // MARK: - Tab 1: 3D Scenes
    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Procedural Signed-Distance Scenes")
                .font(.system(size: 16, weight: .bold))

            Text("Select any raymarched 3D scene to render in real-time ASCII directly on your desktop.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(SceneGeometry.allCases, id: \.rawValue) { scene in
                    sceneCard(scene: scene)
                }
            }
        }
    }

    private func sceneCard(scene: SceneGeometry) -> some View {
        let isSelected = (!config.isCustomMediaActive && config.scene == scene)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                config.scene = scene
                config.customMediaType = .none
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color(simd4: config.fgColor).opacity(0.2) : Color(NSColor.controlColor))
                            .frame(width: 32, height: 32)
                        Image(systemName: scene.sfSymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isSelected ? Color(simd4: config.fgColor) : .secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(simd4: config.fgColor))
                            .font(.system(size: 16))
                    }
                }

                Text(sceneTitle(for: scene))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(scene.category)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color(simd4: config.fgColor) : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sceneTitle(for scene: SceneGeometry) -> String {
        if scene == .mythHologram && config.custom3DText != "MYTH" {
            return "⚡️ 3D \"\(config.custom3DText)\" Cyber Hologram"
        } else if scene == .mythPortal && config.custom3DText != "MYTH" {
            return "🌌 3D \"\(config.custom3DText)\" Cosmic Wormhole"
        }
        return scene.displayName
    }

    // MARK: - Tab 2: Custom Media
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Video, GIF & Image Wallpapers")
                .font(.system(size: 16, weight: .bold))

            Text("Transform your own media files into live ASCII art. Supports videos, animated GIFs, and high-resolution images.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Drag and Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
                    .background(
                        isDropTargeted
                            ? Color.accentColor.opacity(0.08)
                            : Color(NSColor.controlBackgroundColor).opacity(0.4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 8) {
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                        .font(.system(size: 28))
                        .foregroundColor(isDropTargeted ? .accentColor : .secondary)

                    Text(isDropTargeted ? "Drop Media Here" : "Drag & Drop Image, Video, or GIF")
                        .font(.system(size: 13, weight: .medium))

                    Text("Supports .mp4, .mov, .m4v, .gif, .png, .jpg, .heic, .webp")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button("Browse Files...") {
                        chooseCustomMedia()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .frame(height: 160)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url, let device = MTLCreateSystemDefaultDevice() else { return }
                    DispatchQueue.main.async {
                        _ = CustomWallpaperManager.shared.loadAndSetCustomMedia(from: url, device: device)
                    }
                }
                return true
            }

            // Active Media Controls
            if config.isCustomMediaActive {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Custom Wallpaper")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(config.customMediaName ?? "Active")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                        }

                        Spacer()

                        if config.customMediaType == .video || config.customMediaType == .gif {
                            Button {
                                MediaPlaybackEngine.shared.togglePlayPause()
                            } label: {
                                Label(
                                    MediaPlaybackEngine.shared.isPlaying ? "Pause" : "Play",
                                    systemImage: MediaPlaybackEngine.shared.isPlaying ? "pause.fill" : "play.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                        }

                        Button("Clear") {
                            CustomWallpaperManager.shared.clearCustomWallpaper()
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    Toggle(isOn: $config.useTrueColor) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("True Color Mode")
                                .font(.system(size: 13, weight: .medium))
                            Text("When enabled, ASCII characters display the original RGB colors of your media instead of theme tinting.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func chooseCustomMedia() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        CustomWallpaperManager.shared.promptForCustomMedia(device: device) { _ in }
    }

    // MARK: - Tab 3: 3D Text Hologram
    private var text3DSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interactive 3D Text & Hologram Extrusion")
                .font(.system(size: 16, weight: .bold))

            Text("Enter any word, name, or slogan. Palle computes a real-time Euclidean Signed Distance Field (8SSEDT) and extrudes it into 3D inside the Astrolabe and Wormhole scenes.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Text Input Box
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Enter 3D text (e.g. PALLE, CYBER, NEO)", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .onSubmit {
                            apply3DText()
                        }

                    Button("Apply 3D Text") {
                        apply3DText()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to MYTH") {
                        guard let device = MTLCreateSystemDefaultDevice() else { return }
                        CustomTextManager.shared.resetToDefault(device: device)
                        textInput = "MYTH"
                    }
                    .buttonStyle(.bordered)
                }

                // Quick Presets
                HStack(spacing: 6) {
                    Text("Quick Presets:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ForEach(["PALLE", "MYTH", "CYBER", "NEO", "MATRIX", "2026"], id: \.self) { preset in
                        Button(preset) {
                            textInput = preset
                            apply3DText()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(simd4: config.fgColor))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // SDF Telemetry Card
            VStack(alignment: .leading, spacing: 10) {
                Text("8SSEDT Distance Field Telemetry")
                    .font(.system(size: 12, weight: .bold))

                HStack(spacing: 24) {
                    telemetryItem(label: "Current Word", value: config.custom3DText)
                    telemetryItem(label: "Glyph Length", value: "\(config.custom3DText.count) chars")
                    telemetryItem(label: "Aspect Ratio", value: String(format: "%.2f : 1", config.textAspect))
                    telemetryItem(label: "World Bounds", value: String(format: "%.2f × %.2f", config.textHalfW * 2, config.textHalfH * 2))
                    telemetryItem(label: "SDF Format", value: "Metal R8Unorm")
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func telemetryItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func apply3DText() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        _ = CustomTextManager.shared.updateCustomText(textInput, device: device)
    }

    // MARK: - Tab 4: Appearance & Palettes
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Color Themes
            VStack(alignment: .leading, spacing: 12) {
                Text("Color Presets & Themes")
                    .font(.system(size: 16, weight: .bold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(ColorThemePreset.all) { theme in
                        colorThemeCard(theme: theme)
                    }
                }
            }

            Divider()

            // Character Palettes
            VStack(alignment: .leading, spacing: 12) {
                Text("ASCII & Number Art Palettes")
                    .font(.system(size: 16, weight: .bold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(CharacterPalette.allCases, id: \.rawValue) { palette in
                        paletteCard(palette: palette)
                    }
                }
            }
        }
    }

    private func colorThemeCard(theme: ColorThemePreset) -> some View {
        let isSelected = (config.selectedTheme == theme.id)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                config.applyTheme(id: theme.id)
            }
        } label: {
            HStack(spacing: 10) {
                // Dual circle swatch
                ZStack {
                    Circle()
                        .fill(Color(simd4: theme.bg))
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(Color(simd4: theme.fg))
                        .frame(width: 14, height: 14)
                }
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(theme.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(simd4: theme.fg))
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color(simd4: theme.fg) : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func paletteCard(palette: CharacterPalette) -> some View {
        let isSelected = (config.palette == palette)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                config.palette = palette
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(palette.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(simd4: config.fgColor))
                            .font(.system(size: 14))
                    }
                }

                Text(palette.rawValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(simd4: config.fgColor))
                    .lineLimit(1)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color(simd4: config.fgColor) : Color.white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 5: Engine & Performance
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Engine, Performance & Power")
                .font(.system(size: 16, weight: .bold))

            // ASCII Detail & Resolution
            VStack(alignment: .leading, spacing: 8) {
                Text("ASCII Cell Detail & Resolution")
                    .font(.system(size: 13, weight: .semibold))

                Picker("Resolution", selection: $config.fontSize) {
                    ForEach(DetailResolution.allCases, id: \.rawValue) { res in
                        Text(res.displayName).tag(res.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Frame Rate
            VStack(alignment: .leading, spacing: 8) {
                Text("Preferred Frame Rate")
                    .font(.system(size: 13, weight: .semibold))

                Picker("Target FPS", selection: $config.preferredFPS) {
                    Text("30 FPS (Power Saver)").tag(30)
                    Text("60 FPS (Smooth)").tag(60)
                    Text("120 FPS (ProMotion)").tag(120)
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Power & Interaction Toggles
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $config.pauseWhenOccluded) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Occlusion Pause")
                            .font(.system(size: 13, weight: .medium))
                        Text("Freezes Metal GPU rendering and video decoding to 0.0% when full-screen apps or maximized windows cover the desktop.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $config.mouseParallaxEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Mouse Parallax")
                            .font(.system(size: 13, weight: .medium))
                        Text("Dynamically rotates 3D cameras and holographic astrolabe gyro-rings toward your cursor.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Color Helper
extension Color {
    init(simd4: SIMD4<Float>) {
        self.init(
            red: Double(simd4.x),
            green: Double(simd4.y),
            blue: Double(simd4.z),
            opacity: Double(simd4.w)
        )
    }
}
