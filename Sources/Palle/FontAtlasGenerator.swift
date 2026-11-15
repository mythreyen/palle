import Cocoa
import Metal
import CoreText

/// Dynamically generates a crisp, high-DPI horizontal texture strip containing each character
/// in the active `CharacterPalette`. Using CoreText at runtime avoids bundling static bitmap
/// assets and allows instant switching between fonts, character sets, and display scales.
public final class FontAtlasGenerator {

    public static func makeAtlasTexture(
        device: MTLDevice,
        characters: String,
        fontName: String = "Menlo-Bold",
        fontSize: CGFloat = 28.0,
        cellWidth: Int = 24,
        cellHeight: Int = 36
    ) -> MTLTexture? {
        let glyphs = Array(characters)
        let glyphCount = max(glyphs.count, 1)
        let atlasWidth = cellWidth * glyphCount
        let atlasHeight = cellHeight

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)

        guard let context = CGContext(
            data: &rawData,
            width: atlasWidth,
            height: atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: atlasWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))

        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        for (index, char) in glyphs.enumerated() {
            let str = String(char) as NSString
            let size = str.size(withAttributes: attributes)
            let xOffset = CGFloat(index * cellWidth) + (CGFloat(cellWidth) - size.width) * 0.5
            let yOffset = (CGFloat(cellHeight) - size.height) * 0.5
            str.draw(at: NSPoint(x: xOffset, y: yOffset), withAttributes: attributes)
        }

        NSGraphicsContext.restoreGraphicsState()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        let region = MTLRegionMake2D(0, 0, atlasWidth, atlasHeight)
        texture.replace(region: region, mipmapLevel: 0, withBytes: &rawData, bytesPerRow: atlasWidth)

        return texture
    }
}
