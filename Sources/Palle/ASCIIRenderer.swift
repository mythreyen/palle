import Cocoa
import Metal
import MetalKit
import simd

public final class ASCIIRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var fontAtlasTexture: MTLTexture?
    private var fallbackMediaTexture: MTLTexture!
    private var fallbackTextSDFTexture: MTLTexture!

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var mouseNormalized = SIMD2<Float>(0.5, 0.5)
    private var currentPalette: CharacterPalette = .numbers
    private var currentFontSize: CGFloat = 16.0

    public init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        super.init()

        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true

        guard let dummy = makeDummyTexture(),
              let dummySDF = makeDummySDFTexture() else {
            return nil
        }
        self.fallbackMediaTexture = dummy
        self.fallbackTextSDFTexture = dummySDF

        guard buildPipeline(mtkView: mtkView) else {
            return nil
        }
        rebuildFontAtlas()
        setupMouseTracking()
    }

    private func makeDummyTexture() -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        var black: UInt32 = 0
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        return tex
    }

    private func makeDummySDFTexture() -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        var white: UInt8 = 255
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 1)
        return tex
    }

    private func buildPipeline(mtkView: MTKView) -> Bool {
        do {
            // Compile directly from embedded MSL source so both `swift run` and Xcode builds work out of the box
            let library = try device.makeLibrary(source: Self.embeddedMetalSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            return true
        } catch {
            NSLog("[Palle] Failed to compile Metal pipeline: \(error)")
            return false
        }
    }

    public func rebuildFontAtlas() {
        let config = WallpaperConfig.shared
        currentPalette = config.palette
        currentFontSize = config.fontSize

        let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
        let cellW = Int(max(config.fontSize * 0.75 * scale, 12))
        let cellH = Int(max(config.fontSize * 1.35 * scale, 18))

        fontAtlasTexture = FontAtlasGenerator.makeAtlasTexture(
            device: device,
            characters: config.palette.rawValue,
            fontName: "Menlo-Bold",
            fontSize: config.fontSize * 1.25 * scale,
            cellWidth: cellW,
            cellHeight: cellH
        )
    }

    private func setupMouseTracking() {
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            guard WallpaperConfig.shared.mouseParallaxEnabled else { return }
            let loc = NSEvent.mouseLocation
            let targetScreen = NSScreen.screens.first(where: { NSPointInRect(loc, $0.frame) }) ?? NSScreen.main
            guard let screen = targetScreen else { return }
            let localX = loc.x - screen.frame.origin.x
            let localY = loc.y - screen.frame.origin.y
            let nx = Float(max(0.0, min(1.0, localX / max(screen.frame.width, 1.0))))
            let ny = Float(max(0.0, min(1.0, localY / max(screen.frame.height, 1.0))))
            self?.mouseNormalized = SIMD2<Float>(nx, ny)
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        let config = WallpaperConfig.shared
        if config.palette != currentPalette || config.fontSize != currentFontSize {
            rebuildFontAtlas()
        }

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let atlas = fontAtlasTexture else {
            return
        }

        let scale = Float(view.window?.backingScaleFactor ?? 2.0)
        let cellW = Float(max(config.fontSize * 0.75, 5.0)) * scale
        let cellH = Float(max(config.fontSize * 1.35, 8.0)) * scale

        var activeMediaTexture: MTLTexture? = nil
        if config.isCustomMediaActive {
            if config.customMediaType == .video || config.customMediaType == .gif {
                activeMediaTexture = MediaPlaybackEngine.shared.currentFrameTexture()
            } else {
                activeMediaTexture = config.customImageTexture
            }
        }

        let isMedia = (activeMediaTexture != nil) ? Int32(1) : Int32(0)
        let useTrueColor = config.useTrueColor ? Int32(1) : Int32(0)
        let hasCustomText = (config.hasCustomTextSDF && config.textSDFTexture != nil) ? Int32(1) : Int32(0)

        var uniforms = ShaderUniforms(
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            cellSize: SIMD2<Float>(cellW, cellH),
            mouseNormalized: mouseNormalized,
            time: Float(CACurrentMediaTime() - startTime),
            glyphCount: Int32(config.palette.rawValue.count),
            sceneType: config.scene.rawValue,
            cpuLoad: 0.25,
            isCustomMedia: isMedia,
            useTrueColor: useTrueColor,
            fgColor: config.fgColor,
            bgColor: config.bgColor,
            textAspect: config.textAspect,
            textHalfW: config.textHalfW,
            textHalfH: config.textHalfH,
            hasCustomTextSDF: hasCustomText
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(atlas, index: 0)

        let mediaTex = activeMediaTexture ?? fallbackMediaTexture!
        encoder.setFragmentTexture(mediaTex, index: 1)

        let textSDFTex = config.textSDFTexture ?? fallbackTextSDFTexture!
        encoder.setFragmentTexture(textSDFTex, index: 2)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static let embeddedMetalSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 resolution;
    float2 cellSize;
    float2 mouseNormalized;
    float time;
    int glyphCount;
    int sceneType;
    float cpuLoad;
    int isCustomMedia;
    int useTrueColor;
    float4 fgColor;
    float4 bgColor;
    float textAspect;
    float textHalfW;
    float textHalfH;
    int hasCustomTextSDF;
};

// Fullscreen triangle vertex shader (avoids vertex buffer overhead)
vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    VertexOut out;
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = uv;
    return out;
}

// 2D rotation helper
float2x2 rot2D(float a) {
    float s = sin(a), c = cos(a);
    return float2x2(c, -s, s, c);
}

// Line segment distance helper
float fSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// 2D distance to letter strokes of "MYTH"
float dMyth2D(float2 p) {
    float d = 1e5;
    // --- Letter 'M' (centered at x = -1.05) ---
    d = min(d, fSegment(p, float2(-1.28, -0.38), float2(-1.28, 0.38)));
    d = min(d, fSegment(p, float2(-1.28, 0.38), float2(-1.05, -0.05)));
    d = min(d, fSegment(p, float2(-1.05, -0.05), float2(-0.82, 0.38)));
    d = min(d, fSegment(p, float2(-0.82, 0.38), float2(-0.82, -0.38)));

    // --- Letter 'Y' (centered at x = -0.35) ---
    d = min(d, fSegment(p, float2(-0.35, -0.38), float2(-0.35, 0.0)));
    d = min(d, fSegment(p, float2(-0.55, 0.38), float2(-0.35, 0.0)));
    d = min(d, fSegment(p, float2(-0.15, 0.38), float2(-0.35, 0.0)));

    // --- Letter 'T' (centered at x = +0.35) ---
    d = min(d, fSegment(p, float2(0.12, 0.38), float2(0.58, 0.38)));
    d = min(d, fSegment(p, float2(0.35, 0.38), float2(0.35, -0.38)));

    // --- Letter 'H' (centered at x = +1.05) ---
    d = min(d, fSegment(p, float2(0.82, -0.38), float2(0.82, 0.38)));
    d = min(d, fSegment(p, float2(1.28, -0.38), float2(1.28, 0.38)));
    d = min(d, fSegment(p, float2(0.82, 0.0), float2(1.28, 0.0)));

    return d - 0.07;
}

// 2D distance to letter strokes of "MYTH" or custom dynamic text
float sampleText2D(float2 p, constant Uniforms &u, texture2d<float> textSDF, sampler s) {
    if (u.hasCustomTextSDF == 1) {
        float halfW = max(u.textHalfW, 0.2);
        float halfH = max(u.textHalfH, 0.2);
        float2 uv = float2(
            (p.x + halfW) / (2.0 * halfW),
            (halfH - p.y) / (2.0 * halfH)
        );

        float dBox = max(abs(p.x) - halfW, abs(p.y) - halfH);

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return max(dBox + 0.05, 0.05);
        }

        float sdf = textSDF.sample(s, uv).r;
        float dFont = (0.5 - sdf) * (halfH * 0.95);
        return max(dFont, dBox);
    } else {
        return dMyth2D(p);
    }
}

// Signed Distance Function: 3D Scenes
float mapScene(float3 p, constant Uniforms &u, texture2d<float> textSDF, sampler s) {
    if (u.sceneType == 7) {
        // Scene 7: ⚡️ 3D Cyber Hologram & Astrolabe
        float rotX = 0.22 + (u.mouseNormalized.y - 0.5) * 0.9 + sin(u.time * 0.8) * 0.12;
        float rotY = u.time * 0.55 + (u.mouseNormalized.x - 0.5) * 1.2;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        // Wave breathing along X
        float3 pText = p;
        pText.y += sin(pText.x * 2.2 + u.time * 2.5) * 0.06;

        float d2D = sampleText2D(pText.xy, u, textSDF, s);
        float2 w = float2(d2D, abs(pText.z) - 0.14);
        float dText3D = min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - 0.025;

        // Inner beveled neon groove inside letters for extra geometric depth
        float innerGroove = abs(d2D + 0.032) - 0.012;
        innerGroove = max(innerGroove, abs(pText.z) - 0.155);
        dText3D = min(dText3D, innerGroove);

        // Astrolabe Gyro-Rings with precision tick marks & gear notches
        // Ring 1: Horizontal equatorial ring with 32 laser-cut gear tick notches
        float r1 = length(p.xz) - 1.88;
        float theta1 = atan2(p.z, p.x);
        float ticks = sin(theta1 * 32.0);
        float dRing1 = max(abs(r1) - 0.035, abs(p.y) - 0.028);
        if (abs(r1) < 0.06 && ticks > 0.45) {
            dRing1 += 0.015;
        }

        // Ring 2: Tilted double-track precession ring spinning on YZ
        float3 pR2 = p;
        pR2.yz = rot2D(u.time * 1.2) * pR2.yz;
        pR2.xy = rot2D(0.65) * pR2.xy;
        float r2 = length(pR2.xz) - 1.70;
        float dRing2 = max(abs(r2) - 0.045, abs(pR2.y) - 0.028);
        // Slit groove along middle of Ring 2
        dRing2 = max(dRing2, -(max(abs(r2) - 0.012, abs(pR2.y) - 0.04)));

        // Ring 3: Counter-rotating orbital ring
        float3 pR3 = p;
        pR3.xz = rot2D(-u.time * 1.5) * pR3.xz;
        pR3.yz = rot2D(1.1) * pR3.yz;
        float r3 = length(pR3.xy) - 1.52;
        float dRing3 = max(abs(r3) - 0.028, abs(pR3.z) - 0.028);

        // Orbiting glowing plasma satellite beacons
        float orbAngle1 = u.time * 2.2;
        float3 orbPos1 = float3(cos(orbAngle1) * 1.88, sin(orbAngle1 * 2.0) * 0.42, sin(orbAngle1) * 1.88);
        float dOrb1 = length(p - orbPos1) - 0.11;

        float orbAngle2 = -u.time * 1.7;
        float3 orbPos2 = float3(sin(orbAngle2) * 1.62, cos(orbAngle2 * 1.8) * 0.38, cos(orbAngle2) * 1.62);
        float dOrb2 = length(p - orbPos2) - 0.09;

        // Cybernetic hex-pedestal platform at base
        float dPedestal = max(length(p.xz) - 1.95, abs(p.y + 0.92) - 0.02);

        return min(min(min(dText3D, dPedestal), min(dRing1, dRing2)), min(min(dRing3, dOrb1), dOrb2));

    } else if (u.sceneType == 8) {
        // Scene 8: 🌌 3D MYTH Cosmic Wormhole / Relativistic Singularity
        float rotX = 0.55 + (u.mouseNormalized.y - 0.5) * 0.7;
        float rotY = u.time * 0.4 + (u.mouseNormalized.x - 0.5) * 1.0;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        // Gravitational vortex twist
        float distToCenter = length(p.xz);
        float twistAngle = 2.4 / max(distToCenter, 0.35) - u.time * 2.2;
        float3 pVortex = p;
        pVortex.xz = rot2D(twistAngle) * pVortex.xz;

        // Swirling accretion disk with relativistic multi-arm spiral grooves
        float spiralWaves = sin(distToCenter * 8.0 - u.time * 4.0 + atan2(pVortex.z, pVortex.x) * 3.0) * 0.035;
        float disk = abs(p.y) - (0.045 + spiralWaves);
        disk = max(disk, abs(distToCenter - 1.55) - 0.82);

        // Photon ring sphere at r = 1.05
        float photonRing = abs(length(p) - 1.05) - 0.025;

        // Central floating custom text crest above singularity
        float3 pText = p - float3(0.0, 0.45 + sin(u.time * 2.0) * 0.08, 0.0);
        pText.xz = rot2D(u.time * 0.7) * pText.xz;
        float d2D = sampleText2D(pText.xy * 1.4, u, textSDF, s);
        float2 w = float2(d2D, abs(pText.z) - 0.12);
        float dMythCrest = (min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - 0.02) / 1.4;

        float eventHorizon = length(p) - 0.65;
        return min(min(dMythCrest, photonRing), max(disk, -eventHorizon));

    } else if (u.sceneType == 0) {
        // Scene 0: Dual Interlocking Torus / Knot with detailed surface ribs
        float rotX = u.time * 0.45 + (u.mouseNormalized.y - 0.5) * 1.2;
        float rotY = u.time * 0.65 + (u.mouseNormalized.x - 0.5) * 1.2;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        float2 q1 = float2(length(p.xz) - 1.15, p.y);
        float d1 = length(q1) - 0.35;
        float3 p2 = p;
        p2.xy = rot2D(1.570796) * p2.xy;
        float2 q2 = float2(length(p2.xz) - 1.15, p2.y);
        float d2 = length(q2) - 0.35;
        // Dual-frequency surface micro-displacement
        float disp1 = sin(5.0 * p.x + u.time * 2.0) * sin(5.0 * p.y) * 0.055;
        float disp2 = cos(12.0 * p.z) * 0.015;
        return min(d1, d2) + disp1 + disp2;

    } else if (u.sceneType == 1) {
        // Scene 1: 3D Topological Wave Matrix with harmonic sub-ripples
        float rotX = 0.35 + (u.mouseNormalized.y - 0.5) * 0.8;
        float rotY = u.time * 0.35 + (u.mouseNormalized.x - 0.5) * 1.0;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        float wave1 = sin(p.x * 2.2 + u.time * 1.8) * cos(p.z * 2.2 + u.time * 1.4) * 0.45;
        float wave2 = sin(p.x * 5.5 - u.time * 2.4) * cos(p.z * 5.5 + u.time * 2.0) * 0.08;
        return abs(p.y - (wave1 + wave2)) - 0.16;

    } else if (u.sceneType == 2) {
        // Scene 2: Morphing Octahedron + Sphere with faceted star chamfers
        float rotX = u.time * 0.45 + (u.mouseNormalized.y - 0.5) * 1.2;
        float rotY = u.time * 0.65 + (u.mouseNormalized.x - 0.5) * 1.2;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        float3 q = abs(p);
        float oct = (q.x + q.y + q.z - 1.45) * 0.57735027;
        float sph = length(p) - 1.25;
        float blend = 0.5 + 0.5 * sin(u.time * 1.5);
        float core = mix(oct, sph, blend);
        // Beveled faceted outer frame
        float frame = max(oct + 0.08, -sph + 0.05);
        return min(core, frame);

    } else if (u.sceneType == 3) {
        // Scene 3: Festive 3D Christmas Tree & Star with high-density needles
        float rotX = 0.18 + (u.mouseNormalized.y - 0.5) * 0.5;
        float rotY = u.time * 0.65 + (u.mouseNormalized.x - 0.5) * 1.0;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        float branchAngle = atan2(p.z, p.x);
        float needles = sin(branchAngle * 16.0 + p.y * 10.0) * 0.038;

        // 4 Stacked pine tiers
        float h1 = clamp((p.y - (-0.95)) / 0.55, 0.0, 1.0);
        float r1 = mix(1.08, 0.40, h1) + needles;
        float d1 = max(length(p.xz) - r1, max(-p.y - 0.95, p.y + 0.40));

        float h2 = clamp((p.y - (-0.45)) / 0.55, 0.0, 1.0);
        float r2 = mix(0.88, 0.30, h2) + needles;
        float d2 = max(length(p.xz) - r2, max(-p.y - 0.45, p.y + 0.10));

        float h3 = clamp((p.y - 0.05) / 0.55, 0.0, 1.0);
        float r3 = mix(0.66, 0.18, h3) + needles;
        float d3 = max(length(p.xz) - r3, max(-p.y + 0.05, p.y - 0.60));

        float h4 = clamp((p.y - 0.55) / 0.55, 0.0, 1.0);
        float r4 = mix(0.42, 0.04, h4) + needles;
        float d4 = max(length(p.xz) - r4, max(-p.y + 0.55, p.y - 1.10));

        float foliage = min(min(d1, d2), min(d3, d4));

        // Grooved wooden trunk
        float trunkBark = sin(branchAngle * 10.0) * 0.008;
        float dTrunk = max(length(p.xz) - (0.13 + trunkBark), max(-p.y - 1.35, p.y + 0.90));

        // 8-Point Faceted Star topper at apex
        float3 pStar = p - float3(0.0, 1.24, 0.0);
        pStar.xz = rot2D(u.time * 2.0) * pStar.xz;
        float3 qStar = abs(pStar);
        float dStar1 = (qStar.x + qStar.y + qStar.z - 0.18) * 0.57735;
        float3 pStar2 = pStar;
        pStar2.xz = rot2D(0.785) * pStar2.xz;
        float3 qStar2 = abs(pStar2);
        float dStar2 = (qStar2.x + qStar2.y + qStar2.z - 0.18) * 0.57735;
        float dStar = min(dStar1, dStar2);

        // Spherical baubles along branches
        float garlandAngle = p.y * 7.5 + branchAngle * 3.0;
        float expectedRadius = 0.90 - (p.y + 0.9) * 0.36;
        float garlandDist = abs(length(p.xz) - expectedRadius);
        garlandDist = max(garlandDist, abs(sin(garlandAngle)) - 0.055);
        garlandDist = max(garlandDist, max(-p.y - 0.85, p.y - 0.85));

        // Ground snow mound
        float dSnowMound = max(length(p.xz) - 1.45, abs(p.y + 1.25) - 0.08);

        return min(min(min(min(foliage, dTrunk), dStar), garlandDist), dSnowMound);

    } else if (u.sceneType == 4) {
        // Scene 4: Cyber Warp Tunnel with hexagonal ribs & speed tracks
        float3 pT = p;
        float zTravel = pT.z - u.time * 3.6;
        float2 path = float2(
            sin(zTravel * 0.32) * 0.4,
            cos(zTravel * 0.25) * 0.35
        );
        pT.xy -= path;
        float angleT = atan2(pT.y, pT.x);
        float ribs = sin(angleT * 8.0 + zTravel * 1.6) * 0.09 + cos(zTravel * 3.5) * 0.07;
        float microGrooves = sin(angleT * 32.0) * 0.015;
        float radius = 1.35 + ribs + microGrooves;
        return (radius - length(pT.xy)) * 0.7;

    } else if (u.sceneType == 5) {
        // Scene 5: Pulsing Gyroid Crystal with two-scale fractal harmonics
        float rotX = u.time * 0.35 + (u.mouseNormalized.y - 0.5) * 1.0;
        float rotY = u.time * 0.50 + (u.mouseNormalized.x - 0.5) * 1.0;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        float scale = 2.4;
        float3 pG = p * scale;
        // Two-scale harmonic gyroid surface
        float gyroid1 = dot(sin(pG), cos(pG.zxy));
        float gyroid2 = dot(sin(pG * 2.2 + u.time), cos(pG.zxy * 2.2)) * 0.30;
        float gyroid = gyroid1 + gyroid2;
        float thickness = 0.22 + 0.15 * sin(u.time * 2.0);
        float dG = (abs(gyroid) - thickness) / scale;
        float sphereBound = length(p) - (1.35 + 0.1 * sin(u.time * 1.5));
        return max(dG, sphereBound);

    } else {
        // Scene 6: 3D DNA Double Helix with major & minor grooves
        float rotX = 0.25 + (u.mouseNormalized.y - 0.5) * 0.8;
        float rotY = u.time * 0.75 + (u.mouseNormalized.x - 0.5) * 1.2;
        p.yz = rot2D(rotX) * p.yz;
        p.xz = rot2D(rotY) * p.xz;

        float pitch = 2.4;
        float angleH = p.y * pitch + u.time * 1.4;
        float2 strandOffset = float2(cos(angleH), sin(angleH)) * 0.72;

        float dStrandA = length(p.xz - strandOffset) - 0.10;
        float dStrandB = length(p.xz + strandOffset) - 0.10;
        float strands = min(dStrandA, dStrandB);

        float rungRepeat = 0.42;
        float rungY = (fract((p.y + rungRepeat * 0.5) / rungRepeat) - 0.5) * rungRepeat;
        float2 rungDir = strandOffset / 0.72;
        float proj = clamp(dot(p.xz, rungDir), -0.72, 0.72);
        float distToLine = length(p.xz - rungDir * proj);
        float dRung = length(float2(distToLine, rungY)) - 0.055;

        float helix = min(strands, dRung);
        float vBounds = max(p.y - 1.55, -p.y - 1.55);
        return max(helix, vBounds);
    }
}

float3 calcNormal(float3 p, constant Uniforms &u, texture2d<float> textSDF, sampler s) {
    float2 e = float2(0.0015, -0.0015);
    return normalize(
        e.xyy * mapScene(p + e.xyy, u, textSDF, s) +
        e.yyx * mapScene(p + e.yyx, u, textSDF, s) +
        e.yxy * mapScene(p + e.yxy, u, textSDF, s) +
        e.xxx * mapScene(p + e.xxx, u, textSDF, s)
    );
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant Uniforms &u [[buffer(0)]],
    texture2d<float> fontAtlas [[texture(0)]],
    texture2d<float> mediaTexture [[texture(1)]],
    texture2d<float> textSDF [[texture(2)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    // 1. Quantize pixel coordinates into discrete ASCII character cells
    float2 pixelPos = in.uv * u.resolution;
    float2 cellIndex = floor(pixelPos / u.cellSize);
    float2 cellUV = fract(pixelPos / u.cellSize);

    float2 cellCenterPx = (cellIndex + 0.5) * u.cellSize;

    // Fast-path: Custom Media Wallpaper (Images, Photos)
    if (u.isCustomMedia == 1) {
        float mediaW = max(float(mediaTexture.get_width()), 1.0);
        float mediaH = max(float(mediaTexture.get_height()), 1.0);
        float screenAspect = u.resolution.x / max(u.resolution.y, 1.0);
        float mediaAspect = mediaW / mediaH;

        float2 mediaUV = cellCenterPx / u.resolution;
        // Aspect Fill centering
        if (screenAspect > mediaAspect) {
            float scaleY = mediaAspect / screenAspect;
            mediaUV.y = (mediaUV.y - 0.5) * scaleY + 0.5;
        } else {
            float scaleX = screenAspect / mediaAspect;
            mediaUV.x = (mediaUV.x - 0.5) * scaleX + 0.5;
        }

        float4 mediaColor = mediaTexture.sample(texSampler, clamp(mediaUV, 0.0, 1.0));
        float lum = dot(mediaColor.rgb, float3(0.299, 0.587, 0.114));

        int glyphCount = max(u.glyphCount, 2);
        int charIdx = clamp(int(lum * float(glyphCount)), 0, glyphCount - 1);

        float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
        float2 atlasUV = float2(atlasU, cellUV.y);
        float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

        float3 charColor = (u.useTrueColor == 1)
            ? mediaColor.rgb
            : mix(u.fgColor.rgb * 0.45, u.fgColor.rgb * 1.35, lum);

        float3 finalRGB = mix(u.bgColor.rgb, charColor, glyphAlpha);
        return float4(finalRGB, 1.0);
    }

    // Normalized screen coordinate (-1 to 1, aspect-corrected) for 3D raymarching
    float2 ndc = (cellCenterPx / u.resolution) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    ndc.x *= u.resolution.x / max(u.resolution.y, 1.0);

    // 2. High-precision Raymarching (72 steps, 0.0018 threshold)
    float3 ro = float3(0.0, 0.0, (u.sceneType == 4) ? 0.0 : 3.3);
    float3 rd = normalize(float3(ndc, -1.6));

    float t = 0.0;
    float hit = 0.0;
    for (int i = 0; i < 72; ++i) {
        float3 p = ro + rd * t;
        float d = mapScene(p, u, textSDF, texSampler);
        if (d < 0.0018) {
            hit = 1.0;
            break;
        }
        if (t > 8.0) break;
        t += d * 0.88;
    }

    float intensity = 0.0;
    float depthGlow = 0.0;
    float auraGlow = 0.0;

    if (hit > 0.5) {
        float3 p = ro + rd * t;
        float3 n = calcNormal(p, u, textSDF, texSampler);
        float3 viewDir = -rd;

        // Blinn-Phong Specular Reflection
        float3 lightDir = normalize(float3(0.65, 0.85, 1.15));
        float3 halfDir = normalize(lightDir + viewDir);
        float diff = max(dot(n, lightDir), 0.08);
        float spec = pow(max(dot(n, halfDir), 0.0), 28.0) * 0.95;
        float rim = pow(1.0 - max(dot(n, viewDir), 0.0), 2.8);

        // 4-Tap Ambient Occlusion (AO)
        float ao = 0.0;
        float aoWeight = 1.0;
        for (int a = 1; a <= 4; ++a) {
            float hr = 0.035 * float(a);
            float dAo = mapScene(p + n * hr, u, textSDF, texSampler);
            ao += (hr - dAo) * aoWeight;
            aoWeight *= 0.6;
        }
        ao = clamp(1.0 - 2.8 * ao, 0.12, 1.0);

        float fog = exp(-0.16 * t * t);
        float rawLuminance = (diff * 0.68 * ao + spec * 0.50 + rim * 0.42) * fog;
        intensity = clamp(pow(rawLuminance, 0.82), 0.04, 0.999);
        depthGlow = rim;

        // Relativistic Doppler brightening for cosmic wormhole
        if (u.sceneType == 8) {
            float doppler = 1.0 + 0.5 * clamp(p.x, -1.0, 1.0);
            intensity = clamp(intensity * doppler, 0.05, 0.999);
        }

        // Holographic scanning line & shimmer on MYTH
        if (u.sceneType == 7 || u.sceneType == 8) {
            float scanline = sin(p.y * 18.0 - u.time * 6.0);
            if (scanline > 0.65) {
                intensity = clamp(intensity * 1.35 + 0.25, 0.1, 1.0);
                auraGlow = 0.6;
            }
        } else if (u.sceneType == 3) {
            if (p.y > 1.08) {
                auraGlow = 0.5 + 0.5 * sin(u.time * 6.0 + p.x * 12.0);
                intensity = clamp(intensity + auraGlow * 0.5, 0.1, 1.0);
            }
        }
    } else {
        // Dynamic cyber rain / falling particles
        if (u.sceneType == 7 || u.sceneType == 8) {
            float2 rainCoord = float2(pixelPos.x, pixelPos.y + u.time * 40.0);
            float2 rainCell = floor(rainCoord / 24.0);
            float rainHash = fract(sin(dot(rainCell, float2(37.71, 193.37))) * 43758.5453);
            if (rainHash > 0.96) {
                intensity = 0.70;
                auraGlow = 0.35;
            } else {
                float bgHash = fract(sin(dot(cellIndex, float2(12.9898, 78.233)) + floor(u.time * 2.0)) * 43758.5453);
                intensity = (bgHash > 0.94) ? 0.16 : 0.0;
            }
        } else {
            float2 snowCoord = float2(pixelPos.x + sin(pixelPos.y * 0.015 + u.time * 2.0) * 24.0, pixelPos.y + u.time * 60.0);
            float2 snowCell = floor(snowCoord / 22.0);
            float snowHash = fract(sin(dot(snowCell, float2(41.13, 289.71))) * 45758.5453);

            if ((u.sceneType == 3 && snowHash > 0.960) || snowHash > 0.988) {
                intensity = 0.85;
                auraGlow = 0.35;
            } else {
                float bgHash = fract(sin(dot(cellIndex, float2(12.9898, 78.233)) + floor(u.time * 2.0)) * 43758.5453);
                intensity = (bgHash > 0.94) ? 0.16 : 0.0;
            }
        }
    }

    // 3. Map quantized 3D luminance to a glyph index in the horizontal Font Atlas
    int glyphCount = max(u.glyphCount, 2);
    int charIdx = clamp(int(intensity * float(glyphCount)), 0, glyphCount - 1);

    float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
    float2 atlasUV = float2(atlasU, cellUV.y);
    float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

    // 4. Colorize with depth-aware tinting and holographic energy highlights
    float3 activeColor = mix(u.fgColor.rgb * 0.45, u.fgColor.rgb * 1.25, intensity + depthGlow * 0.3);

    if (auraGlow > 0.1) {
        float3 highlightColor = float3(1.0, 0.88, 0.35); // Radiant energy gold
        activeColor = mix(activeColor, highlightColor, auraGlow * 0.75);
    }

    float3 finalRGB = mix(u.bgColor.rgb, activeColor, glyphAlpha * clamp(intensity * 1.4 + 0.15, 0.0, 1.0));

    return float4(finalRGB, 1.0);
}
"""
}
