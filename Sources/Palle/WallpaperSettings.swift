import Foundation
import Metal
import simd

public enum CharacterPalette: String, CaseIterable {
    case mythMatrix = " MYTHmyth0123456789::*#@"
    case mythPure = " MYTH"
    case asciiDensity = " .:-=+*#%@"
    case numbers = " 0123456789"
    case binary = " 01"
    case hex = " 0123456789ABCDEF"
    case matrix = " 012345789Z:.*+=<>|¦"

    public var displayName: String {
        switch self {
        case .mythMatrix: return "⚡️ MYTH Cyber Stream"
        case .mythPure: return "👑 Pure Typography"
        case .asciiDensity: return "Classic ASCII Density"
        case .numbers: return "3D Number Grid (0-9)"
        case .binary: return "Binary Stream (0/1)"
        case .hex: return "Hexadecimal Telemetry"
        case .matrix: return "Cyberpunk Matrix"
        }
    }
}

public enum SceneGeometry: Int32, CaseIterable {
    case matrixRain = 0
    case starfield = 1
    case audioWave = 2
    case telemetryHex = 3
    case asciiBounce = 4

    public var displayName: String {
        switch self {
        case .matrixRain: return "🟢 Matrix Digital Rain"
        case .starfield: return "✨ Retro Starfield"
        case .audioWave: return "🌊 Sine Audio Waveform"
        case .telemetryHex: return "💻 Telemetry Hex Stream"
        case .asciiBounce: return "📼 Bouncing ASCII Emblem"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .matrixRain: return "rain.fill"
        case .starfield: return "sparkles"
        case .audioWave: return "waveform.path"
        case .telemetryHex: return "curlybraces"
        case .asciiBounce: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        }
    }

    public var category: String {
        switch self {
        case .matrixRain: return "Digital Cascading Streams"
        case .starfield: return "Deep Space Warp"
        case .audioWave: return "Oscilloscope Waveform"
        case .telemetryHex: return "Cyberpunk Memory Telemetry"
        case .asciiBounce: return "Classic Retro Screensaver"
        }
    }
}

public enum DetailResolution: CGFloat, CaseIterable {
    case ultra = 9.0
    case high = 12.0
    case standard = 16.0
    case chunky = 22.0

    public var displayName: String {
        switch self {
        case .ultra: return "🔬 Ultra-High Detail (9pt — 25K+ Glyphs)"
        case .high: return "💎 High Detail (12pt — Crisp Contours)"
        case .standard: return "🖥 Standard ASCII (16pt — Classic)"
        case .chunky: return "📟 Retro Chunky (22pt — Big Glyphs)"
        }
    }
}

public enum CustomMediaType: String, Codable {
    case none
    case image
    case video
    case gif
}

public struct ColorThemePreset: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let fg: SIMD4<Float>
    public let bg: SIMD4<Float>
    public let description: String

    public static let all: [ColorThemePreset] = [
        ColorThemePreset(
            id: 0,
            name: "Matrix Mint",
            fg: SIMD4<Float>(0.15, 0.95, 0.65, 1.0),
            bg: SIMD4<Float>(0.03, 0.04, 0.06, 1.0),
            description: "Phosphor terminal green on deep shadow black"
        ),
        ColorThemePreset(
            id: 1,
            name: "Amber CRT",
            fg: SIMD4<Float>(1.00, 0.72, 0.18, 1.0),
            bg: SIMD4<Float>(0.06, 0.04, 0.02, 1.0),
            description: "Vintage retro amber CRT glow"
        ),
        ColorThemePreset(
            id: 2,
            name: "Cyber Cyan",
            fg: SIMD4<Float>(0.20, 0.85, 1.00, 1.0),
            bg: SIMD4<Float>(0.02, 0.04, 0.09, 1.0),
            description: "High-voltage neon cyan on midnight blue"
        ),
        ColorThemePreset(
            id: 3,
            name: "Monochrome Paper",
            fg: SIMD4<Float>(0.92, 0.94, 0.96, 1.0),
            bg: SIMD4<Float>(0.07, 0.07, 0.08, 1.0),
            description: "Clean minimalist newspaper monochrome"
        ),
        ColorThemePreset(
            id: 5,
            name: "Winter Frost",
            fg: SIMD4<Float>(0.65, 0.92, 1.00, 1.0),
            bg: SIMD4<Float>(0.02, 0.05, 0.12, 1.0),
            description: "Glacial ice blue on polar arctic night"
        ),
        ColorThemePreset(
            id: 6,
            name: "Neon Sunset",
            fg: SIMD4<Float>(1.00, 0.35, 0.75, 1.0),
            bg: SIMD4<Float>(0.08, 0.02, 0.12, 1.0),
            description: "Synthwave hot pink on dark twilight violet"
        ),
        ColorThemePreset(
            id: 7,
            name: "Mythic Amethyst & Gold",
            fg: SIMD4<Float>(1.00, 0.85, 0.25, 1.0),
            bg: SIMD4<Float>(0.07, 0.02, 0.12, 1.0),
            description: "Imperial Cyber Gold on Royal Amethyst"
        ),
        ColorThemePreset(
            id: 8,
            name: "Mythic Crimson Cyber",
            fg: SIMD4<Float>(1.00, 0.18, 0.38, 1.0),
            bg: SIMD4<Float>(0.02, 0.04, 0.09, 1.0),
            description: "Laser red overdrive on obsidian slate"
        )
    ]
}

public struct ShaderUniforms {
    public var resolution: SIMD2<Float>
    public var cellSize: SIMD2<Float>
    public var mouseNormalized: SIMD2<Float>
    public var time: Float
    public var glyphCount: Int32
    public var sceneType: Int32
    public var cpuLoad: Float
    public var isCustomMedia: Int32
    public var useTrueColor: Int32
    public var fgColor: SIMD4<Float>
    public var bgColor: SIMD4<Float>
    public var textAspect: Float
    public var textHalfW: Float
    public var textHalfH: Float
    public var hasCustomTextSDF: Int32
}

public final class WallpaperConfig: ObservableObject {
    public static let shared = WallpaperConfig()

    @Published public var palette: CharacterPalette = .matrix
    @Published public var scene: SceneGeometry = .matrixRain
    @Published public var fontSize: CGFloat = 16.0 // Standard ASCII terminal density
    @Published public var preferredFPS: Int = 30 // Lightweight balanced default
    @Published public var pauseWhenOccluded: Bool = true
    @Published public var mouseParallaxEnabled: Bool = true
    @Published public var selectedTheme: Int = 0 // Matrix Mint
    @Published public var fgColor: SIMD4<Float> = SIMD4<Float>(0.15, 0.95, 0.65, 1.0) // Phosphor Terminal Green
    @Published public var bgColor: SIMD4<Float> = SIMD4<Float>(0.03, 0.04, 0.06, 1.0) // Deep Shadow Black

    // Custom Media Wallpaper Support (Images, Videos, GIFs)
    public var customImageTexture: MTLTexture?
    @Published public var customMediaType: CustomMediaType = .none
    @Published public var useTrueColor: Bool = true
    @Published public var customImageName: String?

    public var isCustomMediaActive: Bool {
        return customMediaType != .none
    }

    public var isCustomImageActive: Bool {
        get { customMediaType != .none }
        set { if !newValue { customMediaType = .none } }
    }

    public var customMediaName: String? {
        get { customImageName }
        set { customImageName = newValue }
    }

    // Custom 3D Text Hologram Support
    @Published public var custom3DText: String = "MYTH"
    public var textSDFTexture: MTLTexture?
    @Published public var textAspect: Float = 2.0
    @Published public var textHalfW: Float = 1.15
    @Published public var textHalfH: Float = 0.42
    @Published public var hasCustomTextSDF: Bool = false

    public static let settingsChangedNotification = Notification.Name("PalleSettingsChangedNotification")

    public func notifySettingsChanged() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: nil)
    }

    public func applyTheme(id: Int) {
        if let theme = ColorThemePreset.all.first(where: { $0.id == id }) {
            self.selectedTheme = id
            self.fgColor = theme.fg
            self.bgColor = theme.bg
            notifySettingsChanged()
        }
    }
}
