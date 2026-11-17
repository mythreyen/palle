import Cocoa
import Metal
import MetalKit
import UniformTypeIdentifiers

public final class CustomWallpaperManager {
    public static let shared = CustomWallpaperManager()

    private let userDefaultsPathKey = "PalleLastCustomMediaPath"
    private let userDefaultsTypeKey = "PalleLastCustomMediaType"
    private let legacyImagePathKey = "PalleLastCustomImagePath"
    private let wallpapersDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        wallpapersDir = appSupport.appendingPathComponent("Palle/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)
    }

    /// Presents a native macOS open panel to pick a custom wallpaper (Image, Video, or GIF)
    public func promptForCustomMedia(device: MTLDevice, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "Choose Custom Wallpaper (Image, Video, or GIF)"
            panel.prompt = "Set as Wallpaper"

            let types: [UTType] = [
                .image, .png, .jpeg, .heic, .webP, .tiff,
                .gif,
                .movie, .video, .mpeg4Movie, .quickTimeMovie
            ]
            panel.allowedContentTypes = types
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.level = .floating

            NSApp.activate(ignoringOtherApps: true)

            if panel.runModal() == .OK, let url = panel.url {
                let success = self.loadAndSetCustomMedia(from: url, device: device)
                completion(success)
            } else {
                completion(false)
            }
        }
    }

    /// Backward compatibility alias
    public func promptForCustomImage(device: MTLDevice, completion: @escaping (Bool) -> Void) {
        promptForCustomMedia(device: device, completion: completion)
    }

    /// Ingests media from a URL, caches it, activates playback or static texture, and updates WallpaperConfig
    public func loadAndSetCustomMedia(from url: URL, device: MTLDevice) -> Bool {
        // Cache file into Application Support directory so it persists
        let destURL = wallpapersDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            NSLog("[Palle] Warning: could not copy asset to app support: \(error)")
        }
        let activeURL = FileManager.default.fileExists(atPath: destURL.path) ? destURL : url

        let ext = activeURL.pathExtension.lowercased()
        let config = WallpaperConfig.shared
        let baseName = activeURL.deletingPathExtension().lastPathComponent

        if ext == "gif" {
            let success = MediaPlaybackEngine.shared.loadGIF(url: activeURL, device: device)
            guard success else { return false }

            config.customImageTexture = nil
            config.customMediaType = .gif
            config.customMediaName = baseName

            UserDefaults.standard.set(activeURL.path, forKey: userDefaultsPathKey)
            UserDefaults.standard.set(CustomMediaType.gif.rawValue, forKey: userDefaultsTypeKey)
            NSLog("[Palle] Successfully activated custom GIF loop: \(baseName)")
            return true

        } else if ["mp4", "mov", "m4v", "mkv", "avi"].contains(ext) ||
                    (UTType(filenameExtension: ext)?.conforms(to: .movie) ?? false) {
            let success = MediaPlaybackEngine.shared.loadVideo(url: activeURL, device: device)
            guard success else { return false }

            config.customImageTexture = nil
            config.customMediaType = .video
            config.customMediaName = baseName

            UserDefaults.standard.set(activeURL.path, forKey: userDefaultsPathKey)
            UserDefaults.standard.set(CustomMediaType.video.rawValue, forKey: userDefaultsTypeKey)
            NSLog("[Palle] Successfully activated custom video loop: \(baseName)")
            return true

        } else {
            // Static photo / image
            MediaPlaybackEngine.shared.stop()

            guard let sourceImage = NSImage(contentsOf: activeURL) else {
                NSLog("[Palle] Failed to read image at: \(activeURL.path)")
                return false
            }

            guard let texture = makeOptimizedTexture(from: sourceImage, device: device) else {
                NSLog("[Palle] Failed to create Metal texture from image")
                return false
            }

            config.customImageTexture = texture
            config.customMediaType = .image
            config.customMediaName = baseName

            UserDefaults.standard.set(activeURL.path, forKey: userDefaultsPathKey)
            UserDefaults.standard.set(CustomMediaType.image.rawValue, forKey: userDefaultsTypeKey)
            NSLog("[Palle] Successfully activated custom image: \(baseName)")
            return true
        }
    }

    /// Backward compatibility alias
    public func loadAndSetCustomImage(from url: URL, device: MTLDevice) -> Bool {
        return loadAndSetCustomMedia(from: url, device: device)
    }

    /// Restores previously saved custom wallpaper (image, video, or GIF) on launch, if any
    public func restoreSavedWallpaperIfAny(device: MTLDevice) {
        let savedPath = UserDefaults.standard.string(forKey: userDefaultsPathKey) ??
                        UserDefaults.standard.string(forKey: legacyImagePathKey)

        guard let path = savedPath, FileManager.default.fileExists(atPath: path) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        _ = loadAndSetCustomMedia(from: url, device: device)
    }

    /// Clears custom media and returns to procedural 3D scenes
    public func clearCustomWallpaper() {
        MediaPlaybackEngine.shared.stop()

        let config = WallpaperConfig.shared
        config.customImageTexture = nil
        config.customMediaType = .none
        config.customMediaName = nil

        UserDefaults.standard.removeObject(forKey: userDefaultsPathKey)
        UserDefaults.standard.removeObject(forKey: userDefaultsTypeKey)
        UserDefaults.standard.removeObject(forKey: legacyImagePathKey)
        NSLog("[Palle] Cleared custom media wallpaper, reverted to 3D procedural scenes")
    }

    /// Resizes image to fit max 3840 physical dimension and creates an sRGB Metal texture
    private func makeOptimizedTexture(from image: NSImage, device: MTLDevice) -> MTLTexture? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let origW = cgImage.width
        let origH = cgImage.height
        let maxDim = 3840
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
}
