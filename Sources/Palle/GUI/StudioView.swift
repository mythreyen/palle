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
    @State private var hoveredScene: SceneGeometry?
    @State private var hoveredTheme: Int?
    @State private var showAppliedToast: Bool = false

    public init() {}

    private var accentColor: Color {
        Color(simd4: config.fgColor)
    }

    public var body: some View {
        ZStack {
            // Full-window optical liquid blur
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Glass Sidebar
                sidebarView
                    .frame(width: 230)
                    .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))

                Divider()
                    .overlay(Color.white.opacity(0.12))

                // Detail Content Area
                detailContentView
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .onAppear {
            textInput = config.custom3DText
        }
    }

    // MARK: - Liquid Glass Sidebar
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Monogram Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 3)

                    Image(systemName: "terminal.fill")
                        .foregroundColor(.black)
                        .font(.system(size: 16, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("PALLE")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .tracking(2.0)
                    Text("3D ASCII Studio")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 16)
                .opacity(0.4)

            // Navigation Tabs with Fluid Liquid Pill
            VStack(spacing: 6) {
                ForEach(StudioTab.allCases) { tab in
                    let isCurrent = (selectedTab == tab)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: isCurrent ? .bold : .medium))
                                .foregroundColor(isCurrent ? accentColor : .secondary)
                                .frame(width: 20)

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                                .foregroundColor(isCurrent ? .primary : .secondary)

                            Spacer()

                            if isCurrent {
                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: accentColor, radius: 4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if isCurrent {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [accentColor.opacity(0.6), accentColor.opacity(0.1)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        .shadow(color: accentColor.opacity(0.2), radius: 6, x: 0, y: 2)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            Spacer()

            // Footer Engine Telemetry Pill
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.green.opacity(0.8), radius: 4)

                    Text("Desktop Engine Live")
                        .font(.system(size: 11, weight: .bold))
                }

                Text(activeStatusLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(14)
        }
    }

    private var activeStatusLabel: String {
        if config.isCustomMediaActive {
            return "Media: \(config.customMediaName ?? "Active")"
        } else {
            return "Scene: \(config.scene.displayName)"
        }
    }

    // MARK: - Detail Content
    private var detailContentView: some View {
        VStack(spacing: 0) {
            // Hero Live Mini Viewport Vitrine
            heroViewportVitrine
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .opacity(0.3)

            // Active Tab View Scrollable Container
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 22) {
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
                .padding(22)
            }
        }
    }

    // MARK: - Hero Live Mini Viewport Vitrine
    private var heroViewportVitrine: some View {
        HStack(spacing: 18) {
            // Live 3D Metal ASCII Vitrine Bezel
            ZStack {
                LiveASCIIPreviewView()
                    .frame(width: 240, height: 125)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Curved Glass Reflection Highlight
                VStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                }

                // Shimmering LIVE Badge
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 5, height: 5)
                            Text("LIVE 60 FPS")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                        .padding(8)
                    }
                    Spacer()
                }
            }
            .frame(width: 240, height: 125)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), accentColor.opacity(0.4), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: accentColor.opacity(0.25), radius: 12, x: 0, y: 4)

            // Viewport Information & Status Pills
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(config.isCustomMediaActive ? (config.customMediaName ?? "Custom Media") : config.scene.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)

                    if config.isCustomMediaActive {
                        Text(config.customMediaType.rawValue.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
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

                HStack(spacing: 10) {
                    LiquidGlassBadge(icon: "speedometer", text: "\(config.preferredFPS) FPS", accentColor: accentColor)
                    LiquidGlassBadge(icon: "textformat.size", text: "\(Int(config.fontSize))pt Detail")
                    LiquidGlassBadge(
                        icon: "paintpalette.fill",
                        text: ColorThemePreset.all.first(where: { $0.id == config.selectedTheme })?.name ?? "Custom"
                    )
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 14)
    }

    // MARK: - Tab 1: 3D Scenes
    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Procedural Signed-Distance Scenes")
                    .font(.system(size: 16, weight: .bold))
                Text("Select any raymarched 3D scene to render live on your desktop at 60 FPS.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                ForEach(SceneGeometry.allCases, id: \.rawValue) { scene in
                    sceneLiquidCard(scene: scene)
                }
            }
        }
    }

    private func sceneLiquidCard(scene: SceneGeometry) -> some View {
        let isSelected = (!config.isCustomMediaActive && config.scene == scene)
        let isHovered = (hoveredScene == scene)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                config.scene = scene
                config.customMediaType = .none
                config.notifySettingsChanged()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? accentColor.opacity(0.25) : Color.white.opacity(0.06))
                            .frame(width: 36, height: 36)

                        Image(systemName: scene.sfSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? accentColor : .primary)
                    }

                    Spacer()

                    if isSelected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }

                Text(sceneTitle(for: scene))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(scene.category)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .liquidGlass(
                cornerRadius: 12,
                isSelected: isSelected,
                accentColor: accentColor,
                isHovered: isHovered
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredScene = h ? scene : nil
        }
    }

    private func sceneTitle(for scene: SceneGeometry) -> String {
        if scene == .mythHologram && config.custom3DText != "MYTH" {
            return "⚡️ 3D \"\(config.custom3DText)\" Cyber Hologram"
        } else if scene == .mythPortal && config.custom3DText != "MYTH" {
            return "🌌 3D \"\(config.custom3DText)\" Cosmic Wormhole"
        }
        return scene.displayName
    }

    // MARK: - Tab 2: Custom Media Wallpapers
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Custom Video, GIF & Image Wallpapers")
                    .font(.system(size: 16, weight: .bold))
                Text("Turn your favorite movie loops, anime GIFs, and photos into dynamic ASCII desktop art.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Liquid Glass Drag & Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? accentColor : Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                    )
                    .background(
                        isDropTargeted
                            ? accentColor.opacity(0.12)
                            : Color.white.opacity(0.03)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 10) {
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down.fill")
                        .font(.system(size: 32))
                        .foregroundColor(isDropTargeted ? accentColor : .secondary)

                    Text(isDropTargeted ? "Drop Media to Set Wallpaper" : "Drag & Drop Video, GIF, or Image Here")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Supported: .mp4, .mov, .m4v, .gif, .png, .jpg, .heic, .webp")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button {
                        chooseCustomMedia()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                            Text("Browse Files...")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(accentColor)
                        .clipShape(Capsule())
                        .shadow(color: accentColor.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .frame(height: 180)
            .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.movie.identifier], isTargeted: $isDropTargeted) { providers in
                handleDroppedMedia(providers: providers)
            }

            // Active Media Controller Glass Card
            if config.isCustomMediaActive {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ACTIVE CUSTOM WALLPAPER")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(accentColor)
                            Text(config.customMediaName ?? "Active")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        }

                        Spacer()

                        if config.customMediaType == .video || config.customMediaType == .gif {
                            Button {
                                MediaPlaybackEngine.shared.togglePlayPause()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: MediaPlaybackEngine.shared.isPlaying ? "pause.fill" : "play.fill")
                                    Text(MediaPlaybackEngine.shared.isPlaying ? "Pause" : "Play")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            CustomWallpaperManager.shared.clearCustomWallpaper()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash.fill")
                                Text("Clear")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .opacity(0.3)

                    Toggle(isOn: $config.useTrueColor) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("True Color Mode")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Renders characters using original source RGB colors instead of monochrome theme tinting.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 12, isSelected: true, accentColor: accentColor)
            }
        }
    }

    private func chooseCustomMedia() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        CustomWallpaperManager.shared.promptForCustomMedia(device: device) { _ in }
    }

    private func handleDroppedMedia(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var targetURL: URL?
                if let data = item as? Data {
                    targetURL = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    targetURL = url
                }

                if let url = targetURL {
                    DispatchQueue.main.async {
                        guard let device = MTLCreateSystemDefaultDevice() else { return }
                        _ = CustomWallpaperManager.shared.loadAndSetCustomMedia(from: url, device: device)
                    }
                }
            }
            return true
        }

        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url = url {
                DispatchQueue.main.async {
                    guard let device = MTLCreateSystemDefaultDevice() else { return }
                    _ = CustomWallpaperManager.shared.loadAndSetCustomMedia(from: url, device: device)
                }
            }
        }
        return true
    }

    // MARK: - Tab 3: 3D Text Hologram
    private var text3DSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Interactive 3D Text & Hologram Extrusion")
                    .font(.system(size: 16, weight: .bold))
                Text("Type any custom word or slogan. Palle generates an O(N) Euclidean Signed Distance Field (8SSEDT) and extrudes it live in 3D.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Glass Text Input Box
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Enter text (e.g. PALLE, CYBER, NEO)", text: $textInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .onSubmit {
                            apply3DText()
                        }

                    Button {
                        apply3DText()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Apply 3D Text")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: accentColor.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    Button("Reset to MYTH") {
                        guard let device = MTLCreateSystemDefaultDevice() else { return }
                        CustomTextManager.shared.resetToDefault(device: device)
                        textInput = "MYTH"
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                }

                // Quick Presets
                HStack(spacing: 8) {
                    Text("Presets:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(["PALLE", "MYTH", "CYBER", "NEO", "MATRIX", "2026", "INFINITY"], id: \.self) { preset in
                        Button(preset) {
                            textInput = preset
                            apply3DText()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(accentColor.opacity(0.3), lineWidth: 0.8)
                        )
                    }
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)

            // 8SSEDT Distance Field Telemetry Glass Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cpu.fill")
                        .foregroundColor(accentColor)
                    Text("8SSEDT Distance Field Engine Telemetry")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("Linear O(N) Precision")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 24) {
                    telemetryItem(label: "Current Word", value: config.custom3DText)
                    telemetryItem(label: "Glyph Count", value: "\(config.custom3DText.count) chars")
                    telemetryItem(label: "Aspect Ratio", value: String(format: "%.2f : 1", config.textAspect))
                    telemetryItem(label: "World Bounds", value: String(format: "%.2f × %.2f", config.textHalfW * 2, config.textHalfH * 2))
                    telemetryItem(label: "SDF Format", value: "Metal R8Unorm")
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)
        }
    }

    private func telemetryItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }

    private func apply3DText() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            // If custom media is active or non-hologram scene, switch to 3D Hologram to show the extruded text immediately
            config.customMediaType = .none
            if config.scene != .mythHologram && config.scene != .mythPortal {
                config.scene = .mythHologram
            }
        }
        _ = CustomTextManager.shared.updateCustomText(textInput, device: device)
        config.notifySettingsChanged()
    }

    // MARK: - Tab 4: Appearance & Palettes
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Color Themes
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Color Presets & Themes")
                        .font(.system(size: 16, weight: .bold))
                    Text("Select a color palette. Changes apply immediately to the 3D raymarching shaders.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    ForEach(ColorThemePreset.all) { theme in
                        colorThemeLiquidCard(theme: theme)
                    }
                }
            }

            Divider()
                .opacity(0.3)

            // Character Palettes
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ASCII & Number Art Palettes")
                        .font(.system(size: 16, weight: .bold))
                    Text("Choose the character density ramp used for quantizing 3D luminance.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(CharacterPalette.allCases, id: \.rawValue) { palette in
                        paletteLiquidCard(palette: palette)
                    }
                }
            }
        }
    }

    private func colorThemeLiquidCard(theme: ColorThemePreset) -> some View {
        let isSelected = (config.selectedTheme == theme.id)
        let isHovered = (hoveredTheme == theme.id)
        let themeColor = Color(simd4: theme.fg)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                config.applyTheme(id: theme.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Dual circle swatch
                ZStack {
                    Circle()
                        .fill(Color(simd4: theme.bg))
                        .frame(width: 28, height: 28)
                    Circle()
                        .fill(themeColor)
                        .frame(width: 16, height: 16)
                }
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: themeColor.opacity(0.3), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text(theme.description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(themeColor)
                }
            }
            .padding(12)
            .liquidGlass(
                cornerRadius: 10,
                isSelected: isSelected,
                accentColor: themeColor,
                isHovered: isHovered
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredTheme = h ? theme.id : nil
        }
    }

    private func paletteLiquidCard(palette: CharacterPalette) -> some View {
        let isSelected = (config.palette == palette)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                config.palette = palette
                config.notifySettingsChanged()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(palette.displayName)
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(accentColor)
                            .font(.system(size: 14))
                    }
                }

                Text(palette.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(accentColor)
                    .lineLimit(1)
            }
            .padding(12)
            .liquidGlass(
                cornerRadius: 10,
                isSelected: isSelected,
                accentColor: accentColor
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 5: Engine & Performance
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Engine, Performance & Power")
                    .font(.system(size: 16, weight: .bold))
                Text("Fine-tune rendering quality, hardware frame rate, and power throttling.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // ASCII Cell Detail & Resolution Liquid Selector
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ASCII Cell Detail & Resolution")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(Int(config.fontSize))pt Font Atlas")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(accentColor)
                }

                Picker("Resolution", selection: $config.fontSize) {
                    ForEach(DetailResolution.allCases, id: \.rawValue) { res in
                        Text(res.displayName).tag(res.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: config.fontSize) { _ in
                    config.notifySettingsChanged()
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)

            // Target Frame Rate Liquid Selector
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preferred Refresh Rate")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(config.preferredFPS) FPS")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(accentColor)
                }

                Picker("Target FPS", selection: $config.preferredFPS) {
                    Text("30 FPS (Power Saver)").tag(30)
                    Text("60 FPS (Smooth)").tag(60)
                    Text("120 FPS (ProMotion Ultra)").tag(120)
                }
                .pickerStyle(.segmented)
                .onChange(of: config.preferredFPS) { _ in
                    config.notifySettingsChanged()
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)

            // Power & Interaction Switches
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $config.pauseWhenOccluded) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Occlusion Pause")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Drops GPU rendering and video decoding to 0.0% when windows cover >= 92% of the desktop.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()
                    .opacity(0.3)

                Toggle(isOn: $config.mouseParallaxEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Mouse Parallax")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Smoothly tilts 3D cameras and astrolabe gyro-rings toward your cursor.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)

            // Hardware Telemetry Glass Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "macmini.fill")
                        .foregroundColor(accentColor)
                    Text("Hardware Architecture Telemetry")
                        .font(.system(size: 12, weight: .bold))
                }

                HStack(spacing: 24) {
                    telemetryItem(label: "Metal GPU", value: MTLCreateSystemDefaultDevice()?.name ?? "Apple Metal")
                    telemetryItem(label: "Pixel Format", value: "BGRA8Unorm")
                    telemetryItem(label: "Memory Footprint", value: "< 30 MB")
                    telemetryItem(label: "Displays", value: "\(NSScreen.screens.count) Active")
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 12)
        }
    }
}
