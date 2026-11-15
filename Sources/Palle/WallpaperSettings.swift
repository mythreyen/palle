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
    case festive = " .·*+oO#@▲★❄"
    case holidayASCII = " .*+o8#@^~|"

    public var displayName: String {
        switch self {
        case .mythMatrix: return "⚡️ MYTH Cyber Stream"
        case .mythPure: return "👑 Pure MYTH Typography"
        case .asciiDensity: return "Classic ASCII Density"
        case .numbers: return "3D Number Grid (0-9)"
        case .binary: return "Binary Stream (0/1)"
        case .hex: return "Hexadecimal Telemetry"
        case .matrix: return "Cyberpunk Matrix"
        case .festive: return "❄️ Holiday Snow & Stars"
        case .holidayASCII: return "🎄 Festive ASCII Art"
        }
    }
}

public enum SceneGeometry: Int32, CaseIterable {
    case mythHologram = 7
    case mythPortal = 8
    case torusKnot = 0
    case numberWave = 1
    case octoFractal = 2
    case christmasTree = 3
    case warpTunnel = 4
    case pulsingGyroid = 5
    case dnaHelix = 6

    public var displayName: String {
        switch self {
        case .mythHologram: return "⚡️ 3D MYTH Cyber Hologram"
        case .mythPortal: return "🌌 3D MYTH Cosmic Wormhole"
        case .torusKnot: return "3D Torus Knot"
        case .numberWave: return "Topological Number Wave"
        case .octoFractal: return "Morphing Octahedron"
        case .christmasTree: return "🎄 3D Christmas Tree & Snow"
        case .warpTunnel: return "🌀 Cyber Warp Tunnel"
        case .pulsingGyroid: return "💎 Pulsing Gyroid Crystal"
        case .dnaHelix: return "🧬 3D Double Helix"
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

    @Published public var palette: CharacterPalette = .mythMatrix
    @Published public var scene: SceneGeometry = .mythHologram
    @Published public var fontSize: CGFloat = 12.0 // Default to High Detail
    @Published public var preferredFPS: Int = 60
    @Published public var pauseWhenOccluded: Bool = true
    @Published public var mouseParallaxEnabled: Bool = true
    @Published public var selectedTheme: Int = 7 // Mythic Amethyst & Gold
    @Published public var fgColor: SIMD4<Float> = SIMD4<Float>(1.00, 0.85, 0.25, 1.0) // Imperial Cyber Gold
    @Published public var bgColor: SIMD4<Float> = SIMD4<Float>(0.07, 0.02, 0.12, 1.0) // Deep Royal Amethyst

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
}
