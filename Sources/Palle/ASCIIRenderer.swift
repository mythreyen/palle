import Cocoa
import Metal
import MetalKit
import simd

/// Consolidated global mouse tracker throttled to display rate, avoiding multiple redundant monitors
public final class SharedMouseTracker {
    public static let shared = SharedMouseTracker()
    private var monitor: Any?
    private var lastUpdateTime: CFTimeInterval = 0
    public private(set) var normalizedPos = SIMD2<Float>(0.5, 0.5)

    private init() {
        startTracking()
    }

    public func startTracking() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            guard let self = self, WallpaperConfig.shared.mouseParallaxEnabled else { return }
            let now = CACurrentMediaTime()
            // Throttle to 60Hz to prevent CPU thrashing on 1000Hz gaming mice
            guard now - self.lastUpdateTime >= 0.016 else { return }
            self.lastUpdateTime = now

            let loc = NSEvent.mouseLocation
            let targetScreen = NSScreen.screens.first(where: { NSPointInRect(loc, $0.frame) }) ?? NSScreen.main
            guard let screen = targetScreen else { return }
            let localX = loc.x - screen.frame.origin.x
            let localY = loc.y - screen.frame.origin.y
            let nx = Float(max(0.0, min(1.0, localX / max(screen.frame.width, 1.0))))
            let ny = Float(max(0.0, min(1.0, localY / max(screen.frame.height, 1.0))))
            self.normalizedPos = SIMD2<Float>(nx, ny)
        }
    }
}

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
        SharedMouseTracker.shared.startTracking()
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

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        let config = WallpaperConfig.shared
        if config.palette != currentPalette || config.fontSize != currentFontSize {
            rebuildFontAtlas()
        }
        if config.mouseParallaxEnabled {
            mouseNormalized = SharedMouseTracker.shared.normalizedPos
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

// Fast hash helpers
float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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
    int glyphCount = max(u.glyphCount, 2);

    // Fast-path: Custom Media Wallpaper (Images, Photos, Videos, GIFs)
    if (u.isCustomMedia == 1) {
        float mediaW = max(float(mediaTexture.get_width()), 1.0);
        float mediaH = max(float(mediaTexture.get_height()), 1.0);
        float screenAspect = u.resolution.x / max(u.resolution.y, 1.0);
        float mediaAspect = mediaW / mediaH;

        float2 mediaUV = cellCenterPx / u.resolution;
        if (screenAspect > mediaAspect) {
            float scaleY = mediaAspect / screenAspect;
            mediaUV.y = (mediaUV.y - 0.5) * scaleY + 0.5;
        } else {
            float scaleX = screenAspect / mediaAspect;
            mediaUV.x = (mediaUV.x - 0.5) * scaleX + 0.5;
        }

        float4 mediaColor = mediaTexture.sample(texSampler, clamp(mediaUV, 0.0, 1.0));
        float lum = dot(mediaColor.rgb, float3(0.299, 0.587, 0.114));

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

    float2 gridDim = floor(u.resolution / u.cellSize);

    // =========================================================================
    // Scene 0: 🟢 Matrix Digital Rain (Cascading streams, mutating glyphs)
    // =========================================================================
    if (u.sceneType == 0) {
        float col = cellIndex.x;
        float row = cellIndex.y;
        float numRows = max(gridDim.y, 1.0);

        // Stream 1 (Primary cascade)
        float speed1 = mix(14.0, 30.0, hash11(col * 13.37));
        float len1 = mix(10.0, 26.0, hash11(col * 47.19));
        float cycle1 = numRows + len1 + 8.0;
        float head1 = fmod(u.time * speed1 + hash11(col * 91.13) * cycle1, cycle1) - len1 * 0.5;
        float dist1 = head1 - row;

        float int1 = 0.0;
        float isHead1 = 0.0;
        if (dist1 >= 0.0 && dist1 < len1) {
            if (dist1 < 1.1) {
                isHead1 = 1.0;
                int1 = 1.0;
            } else {
                int1 = pow(1.0 - (dist1 / len1), 1.45) * 0.88;
            }
        }

        // Stream 2 (Secondary staggered cascade)
        float speed2 = mix(11.0, 24.0, hash11(col * 83.21));
        float len2 = mix(8.0, 20.0, hash11(col * 29.43));
        float cycle2 = numRows + len2 + 16.0;
        float head2 = fmod(u.time * speed2 + hash11(col * 53.67) * cycle2 + cycle2 * 0.52, cycle2) - len2 * 0.5;
        float dist2 = head2 - row;

        float int2 = 0.0;
        float isHead2 = 0.0;
        if (dist2 >= 0.0 && dist2 < len2) {
            if (dist2 < 1.1) {
                isHead2 = 1.0;
                int2 = 1.0;
            } else {
                int2 = pow(1.0 - (dist2 / len2), 1.45) * 0.88;
            }
        }

        float intensity = max(int1, int2);
        float isHead = max(isHead1, isHead2);

        if (intensity <= 0.015) {
            return float4(u.bgColor.rgb, 1.0);
        }

        // Mutation: leading head characters mutate fast (16Hz); body at 2.5Hz
        float mutRate = (isHead > 0.5) ? 16.0 : ((intensity > 0.35) ? 2.5 : 0.4);
        float glyphSeed = hash21(float2(col * 17.1 + floor(u.time * mutRate) * 0.31, row * 31.7));
        int charIdx = clamp(int(glyphSeed * float(glyphCount - 1)) + 1, 1, glyphCount - 1);

        float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
        float2 atlasUV = float2(atlasU, cellUV.y);
        float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

        float3 headColor = mix(u.fgColor.rgb * 1.35, float3(0.95, 1.0, 0.95), 0.88);
        float3 bodyColor = mix(u.fgColor.rgb * 0.45, u.fgColor.rgb * 1.15, intensity);
        float3 charColor = (isHead > 0.5) ? headColor : bodyColor;

        float3 finalRGB = mix(u.bgColor.rgb, charColor, glyphAlpha * clamp(intensity * 1.5, 0.0, 1.0));
        return float4(finalRGB, 1.0);
    }

    // =========================================================================
    // Scene 1: ✨ Retro Starfield (Radial warp with parallax mouse steering)
    // =========================================================================
    if (u.sceneType == 1) {
        float2 center = gridDim * 0.5 + (u.mouseNormalized - 0.5) * gridDim * 0.35;
        float2 p = cellIndex - center;
        float r = length(p);
        float theta = atan2(p.y, p.x);

        float sectorCount = 120.0;
        float sector = floor((theta + 3.14159265) / (6.2831853 / sectorCount));
        float sectorHash = hash11(sector * 19.17);

        float starSpeed = mix(18.0, 50.0, sectorHash);
        float maxR = length(gridDim * 0.5) * 1.1;
        float starPos = fmod(u.time * starSpeed + hash11(sector * 71.3) * maxR, maxR);

        float distR = abs(r - starPos);
        float streak = clamp((starPos - r) / max(starPos * 0.18, 1.5), 0.0, 1.0);

        float intensity = 0.0;
        if (distR < 1.0) {
            intensity = 0.95;
        } else if (r < starPos && streak > 0.01) {
            intensity = pow(1.0 - streak, 1.2) * 0.65;
        }

        float centerFade = smoothstep(1.5, 8.0, r);
        intensity *= centerFade;

        if (intensity <= 0.015) {
            return float4(u.bgColor.rgb, 1.0);
        }

        int charIdx = clamp(int(intensity * float(glyphCount)), 0, glyphCount - 1);
        float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
        float2 atlasUV = float2(atlasU, cellUV.y);
        float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

        float3 starColor = mix(u.fgColor.rgb * 0.6, float3(1.0, 1.0, 1.0), intensity * 0.75);
        float3 finalRGB = mix(u.bgColor.rgb, starColor, glyphAlpha * intensity);
        return float4(finalRGB, 1.0);
    }

    // =========================================================================
    // Scene 2: 🌊 Sine Audio Waveform (Multi-frequency oscilloscope)
    // =========================================================================
    if (u.sceneType == 2) {
        float xNorm = cellIndex.x / max(gridDim.x, 1.0);

        float w1 = sin(xNorm * 9.4 - u.time * 3.5) * 0.16;
        float w2 = sin(xNorm * 18.8 + u.time * 2.8) * 0.09;
        float w3 = sin(xNorm * 37.6 - u.time * 5.2) * 0.04;
        float w4 = cos(xNorm * 4.2 + u.time * 1.4) * 0.12;

        float2 mouseCell = u.mouseNormalized * gridDim;
        float distToMouse = length(cellIndex - mouseCell);
        float ripple = sin(distToMouse * 0.28 - u.time * 6.0) * exp(-distToMouse * 0.04) * 0.14;

        float waveYNorm = 0.5 + (w1 + w2 + w3 + w4 + ripple);
        float cellYNorm = cellIndex.y / max(gridDim.y, 1.0);
        float rowDist = abs(cellYNorm - waveYNorm) * gridDim.y;

        float beam = exp(-rowDist * 0.95);
        float glow = exp(-rowDist * 0.16) * 0.40;
        float intensity = clamp(beam * 1.1 + glow, 0.0, 1.0);

        if (intensity <= 0.02) {
            return float4(u.bgColor.rgb, 1.0);
        }

        int charIdx = clamp(int(intensity * float(glyphCount)), 0, glyphCount - 1);
        float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
        float2 atlasUV = float2(atlasU, cellUV.y);
        float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

        float3 beamColor = mix(u.fgColor.rgb * 0.6, float3(0.92, 1.0, 0.95), beam);
        float3 finalRGB = mix(u.bgColor.rgb, beamColor, glyphAlpha * intensity);
        return float4(finalRGB, 1.0);
    }

    // =========================================================================
    // Scene 3: 💻 Telemetry Hex Stream (Cyberpunk memory telemetry dump)
    // =========================================================================
    if (u.sceneType == 3) {
        float scroll = u.time * 7.5;
        float row = cellIndex.y + floor(scroll);
        float col = cellIndex.x;
        float colMod = fmod(col, 36.0);

        float glyphSeed = 0.0;
        float intensity = 0.70;
        float isHighlight = 0.0;

        float activity = hash21(float2(col * 3.1 + floor(u.time * 4.0), row));
        if (activity > 0.95) {
            isHighlight = 1.0;
            intensity = 1.0;
        }

        if (colMod < 8.0) {
            intensity = 0.55;
            glyphSeed = hash21(float2(colMod, row * 0.5));
        } else if (colMod == 8.0 || colMod == 9.0) {
            return float4(u.bgColor.rgb, 1.0);
        } else if (colMod >= 10.0 && colMod < 32.0) {
            float byteCol = colMod - 10.0;
            if (fmod(byteCol, 3.0) == 2.0) {
                return float4(u.bgColor.rgb, 1.0);
            }
            glyphSeed = hash21(float2(floor(byteCol / 3.0) * 11.3, row));
        } else {
            glyphSeed = hash21(float2(colMod * 7.7, row));
        }

        int charIdx = clamp(int(glyphSeed * float(glyphCount - 1)) + 1, 1, glyphCount - 1);
        float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
        float2 atlasUV = float2(atlasU, cellUV.y);
        float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

        float3 charColor = (isHighlight > 0.5)
            ? mix(u.fgColor.rgb * 1.5, float3(1.0, 1.0, 0.8), 0.7)
            : u.fgColor.rgb * intensity;

        float3 finalRGB = mix(u.bgColor.rgb, charColor, glyphAlpha * intensity);
        return float4(finalRGB, 1.0);
    }

    // =========================================================================
    // Scene 4: 📼 Bouncing ASCII Emblem (Retro corner-bouncing screensaver)
    // =========================================================================
    {
        float screenAspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 pScreen = (cellCenterPx / u.resolution) * 2.0 - 1.0;
        pScreen.y = -pScreen.y;
        pScreen.x *= screenAspect;

        float halfW = max(u.textHalfW * 0.55, 0.45);
        float halfH = max(u.textHalfH * 0.55, 0.20);
        float boundX = max(screenAspect - halfW - 0.1, 0.2);
        float boundY = max(1.0 - halfH - 0.1, 0.2);

        float tX = u.time * 0.38;
        float tY = u.time * 0.29;
        float posX = (abs(fmod(tX, 4.0) - 2.0) - 1.0) * boundX;
        float posY = (abs(fmod(tY, 4.0) - 2.0) - 1.0) * boundY;

        float2 pBox = pScreen - float2(posX, posY);
        float dText = sampleText2D(pBox / 0.55, u, textSDF, texSampler) * 0.55;

        float dBorder = max(abs(pBox.x) - halfW, abs(pBox.y) - halfH);
        float borderStroke = abs(dBorder) - 0.015;

        float dist = min(dText, borderStroke);
        float intensity = clamp(1.0 - dist * 14.0, 0.0, 1.0);
        if (dText < 0.02) intensity = 1.0;

        float nearCorner = max(1.0 - length(float2(abs(posX) - boundX, abs(posY) - boundY)) * 4.0, 0.0);
        intensity += nearCorner * 0.3;

        if (intensity <= 0.02) {
            return float4(u.bgColor.rgb, 1.0);
        }

        int charIdx = clamp(int(intensity * float(glyphCount)), 0, glyphCount - 1);
        float atlasU = (float(charIdx) + cellUV.x) / float(glyphCount);
        float2 atlasUV = float2(atlasU, cellUV.y);
        float glyphAlpha = fontAtlas.sample(texSampler, atlasUV).r;

        float3 emblemColor = mix(u.fgColor.rgb * 0.7, float3(1.0, 1.0, 1.0), intensity * 0.4 + nearCorner * 0.4);
        float3 finalRGB = mix(u.bgColor.rgb, emblemColor, glyphAlpha * intensity);
        return float4(finalRGB, 1.0);
    }
}
"""
}
