import AVFoundation
import Cocoa
import CoreVideo
import ImageIO
import Metal

/// Hardware-accelerated video & animated GIF loop playback engine for Palle.
/// Streams frames directly to Metal textures via CVMetalTextureCache with zero CPU memory copying.
public final class MediaPlaybackEngine: NSObject {
    public static let shared = MediaPlaybackEngine()

    private var device: MTLDevice?
    private var textureCache: CVMetalTextureCache?
    private var player: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var currentTexture: MTLTexture?
    private var playerItemObserver: Any?

    private var isPaused: Bool = false
    public private(set) var isVideoLoaded: Bool = false
    public private(set) var isGifLoaded: Bool = false

    // Animated GIF state
    private struct GIFFrame {
        let texture: MTLTexture
        let targetTime: Double
    }
    private var gifFrames: [GIFFrame] = []
    private var gifTotalDuration: Double = 0.0
    private var gifStartTime: CFTimeInterval = 0.0
    private var gifPauseOffset: CFTimeInterval = 0.0

    public var isPlaying: Bool {
        if isVideoLoaded {
            return (player?.rate ?? 0) > 0 && !isPaused
        }
        if isGifLoaded {
            return !isPaused
        }
        return false
    }

    private override init() {
        super.init()
    }

    deinit {
        stop()
    }

    /// Initializes or reuses the CoreVideo Metal Texture Cache for zero-copy texture streaming
    public func ensureTextureCache(device: MTLDevice) {
        if self.textureCache == nil {
            self.device = device
            var cache: CVMetalTextureCache?
            let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            if result == kCVReturnSuccess {
                self.textureCache = cache
            } else {
                NSLog("[Palle] Failed to create CVMetalTextureCache (status: \(result))")
            }
        }
    }

    /// Loads and starts seamless looping playback of a video file (.mp4, .mov, .m4v)
    public func loadVideo(url: URL, device: MTLDevice) -> Bool {
        stop()
        ensureTextureCache(device: device)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        item.add(output)

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .none
        newPlayer.isMuted = true
        newPlayer.volume = 0.0

        self.playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if !(self?.isPaused ?? false) {
                    self?.player?.play()
                }
            }
        }

        self.videoOutput = output
        self.player = newPlayer
        self.isVideoLoaded = true
        self.isGifLoaded = false
        self.isPaused = false

        newPlayer.play()
        NSLog("[Palle] Loaded video loop: \(url.lastPathComponent)")
        return true
    }

    /// Loads and starts looping playback of an animated GIF (.gif)
    public func loadGIF(url: URL, device: MTLDevice) -> Bool {
        stop()
        ensureTextureCache(device: device)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            NSLog("[Palle] Failed to open GIF at: \(url.path)")
            return false
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else {
            NSLog("[Palle] GIF has no frames: \(url.path)")
            return false
        }

        var frames: [GIFFrame] = []
        var cumulativeTime: Double = 0.0
        let maxFrames = min(count, 300) // Cap to prevent excessive memory on huge GIFs

        for i in 0..<maxFrames {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            var frameDuration: Double = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0.01 {
                    frameDuration = unclamped
                } else if let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double, delay > 0.01 {
                    frameDuration = delay
                }
            }

            if let tex = makeTexture(from: cgImage, device: device) {
                cumulativeTime += frameDuration
                frames.append(GIFFrame(texture: tex, targetTime: cumulativeTime))
            }
        }

        guard !frames.isEmpty else {
            NSLog("[Palle] No valid frames extracted from GIF")
            return false
        }

        self.gifFrames = frames
        self.gifTotalDuration = max(cumulativeTime, 0.05)
        self.gifStartTime = CACurrentMediaTime()
        self.gifPauseOffset = 0.0
        self.isGifLoaded = true
        self.isVideoLoaded = false
        self.isPaused = false
        self.currentTexture = frames.first?.texture

        NSLog("[Palle] Loaded animated GIF (\(frames.count) frames, duration: \(String(format: "%.2f", gifTotalDuration))s)")
        return true
    }

    /// Returns the current active frame texture for rendering, or nil if none loaded
    public func currentFrameTexture() -> MTLTexture? {
        if isGifLoaded {
            return currentGIFTexture()
        }
        if isVideoLoaded {
            return currentVideoTexture()
        }
        return nil
    }

    private func currentVideoTexture() -> MTLTexture? {
        guard let videoOutput = videoOutput,
              let item = player?.currentItem,
              item.status == .readyToPlay else {
            return currentTexture
        }

        let hostTime = CACurrentMediaTime()
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)

        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                updateTexture(from: pixelBuffer)
            }
        } else if currentTexture == nil {
            // Initial frame warmup if not yet delivered
            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                updateTexture(from: pixelBuffer)
            }
        }

        return currentTexture
    }

    private func currentGIFTexture() -> MTLTexture? {
        guard !gifFrames.isEmpty, gifTotalDuration > 0 else { return currentTexture }

        let now = isPaused ? gifPauseOffset : CACurrentMediaTime()
        let elapsed = (now - gifStartTime).truncatingRemainder(dividingBy: gifTotalDuration)
        let positiveElapsed = elapsed >= 0 ? elapsed : elapsed + gifTotalDuration

        for frame in gifFrames {
            if positiveElapsed <= frame.targetTime {
                currentTexture = frame.texture
                return frame.texture
            }
        }

        currentTexture = gifFrames.last?.texture
        return currentTexture
    }

    private func updateTexture(from pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        if status == kCVReturnSuccess, let cvTexture = cvTexture {
            self.currentTexture = CVMetalTextureGetTexture(cvTexture)
        }
    }

    private func makeTexture(from cgImage: CGImage, device: MTLDevice) -> MTLTexture? {
        let origW = cgImage.width
        let origH = cgImage.height
        let maxDim = 1920
        let scale = min(1.0, CGFloat(maxDim) / CGFloat(max(origW, origH)))

        let targetW = max(1, Int(CGFloat(origW) * scale))
        let targetH = max(1, Int(CGFloat(origH) * scale))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = targetW * 4
        var rawData = [UInt8](repeating: 0, count: targetH * bytesPerRow)

        guard let context = CGContext(
            data: &rawData,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: targetW,
            height: targetH,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        let region = MTLRegionMake2D(0, 0, targetW, targetH)
        texture.replace(region: region, mipmapLevel: 0, withBytes: &rawData, bytesPerRow: bytesPerRow)

        return texture
    }

    /// Pauses playback and freezes video decoding for zero background resource consumption
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        if isVideoLoaded {
            player?.pause()
        }
        if isGifLoaded {
            gifPauseOffset = CACurrentMediaTime()
        }
    }

    /// Resumes playback from the exact pause point
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        if isVideoLoaded {
            player?.play()
        }
        if isGifLoaded {
            let pauseDuration = CACurrentMediaTime() - gifPauseOffset
            gifStartTime += pauseDuration
        }
    }

    /// Toggles play/pause state
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Completely stops playback and frees all video/GIF textures and observers
    public func stop() {
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
        player?.pause()
        player = nil
        videoOutput = nil
        currentTexture = nil
        gifFrames.removeAll()
        isVideoLoaded = false
        isGifLoaded = false
        isPaused = false
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
}
