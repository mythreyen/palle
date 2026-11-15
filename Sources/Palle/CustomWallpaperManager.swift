import Cocoa
import Metal
import MetalKit

public final class CustomWallpaperManager {
    public static let shared = CustomWallpaperManager()

    private let userDefaultsKey = "PalleLastCustomImagePath"
    private let wallpapersDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        wallpapersDir = appSupport.appendingPathComponent("Palle/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)
    }

    /// Presents a native macOS open panel to pick a custom image wallpaper
    public func promptForCustomImage(device: MTLDevice, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "Choose Custom Wallpaper Image"
            panel.prompt = "Set as Wallpaper"
            panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .webP, .tiff]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false

            // Ensure app is temporarily active to display panel above other apps
            NSApp.activate(ignoringOtherApps: true)

            if panel.runModal() == .OK, let url = panel.url {
                let success = self.loadAndSetCustomImage(from: url, device: device)
                completion(success)
            } else {
                completion(false)
            }
        }
    }

    /// Loads an image from a URL, creates an optimized Metal texture, and updates WallpaperConfig
    public func loadAndSetCustomImage(from url: URL, device: MTLDevice) -> Bool {
        guard let sourceImage = NSImage(contentsOf: url) else {
            NSLog("[Palle] Failed to read image at: \(url.path)")
            return false
        }

        guard let texture = makeOptimizedTexture(from: sourceImage, device: device) else {
            NSLog("[Palle] Failed to create Metal texture from image")
            return false
        }

        // Cache file into Application Support directory so it persists
        let destURL = wallpapersDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)
        try? FileManager.default.copyItem(at: url, to: destURL)
        UserDefaults.standard.set(destURL.path, forKey: userDefaultsKey)

        let config = WallpaperConfig.shared
        config.customImageTexture = texture
        config.customImageName = url.deletingPathExtension().lastPathComponent
        config.isCustomImageActive = true

        NSLog("[Palle] Successfully loaded custom wallpaper: \(url.lastPathComponent)")
        return true
    }

    /// Restores previously saved custom wallpaper on launch, if any
    public func restoreSavedWallpaperIfAny(device: MTLDevice) {
        guard let savedPath = UserDefaults.standard.string(forKey: userDefaultsKey),
              FileManager.default.fileExists(atPath: savedPath) else {
            return
        }
        let url = URL(fileURLWithPath: savedPath)
        _ = loadAndSetCustomImage(from: url, device: device)
    }

    /// Clears custom image and returns to procedural 3D scenes
    public func clearCustomWallpaper() {
        let config = WallpaperConfig.shared
        config.customImageTexture = nil
        config.isCustomImageActive = false
        config.customImageName = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        NSLog("[Palle] Cleared custom wallpaper, reverted to 3D procedural scenes")
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
