import Cocoa
import Metal

public struct TextSDFResult {
    public let texture: MTLTexture
    public let aspect: Float
    public let halfW: Float
    public let halfH: Float
}

/// Generates high-precision 2D Signed Distance Field (SDF) textures for arbitrary strings
/// using the 8-point Signed Sequential Euclidean Distance Transform (8SSEDT) in O(N) time.
public final class TextSDFGenerator {

    private struct GridPoint {
        var dx: Int32
        var dy: Int32

        var distSq: Int32 {
            return dx * dx + dy * dy
        }

        static let infinity = GridPoint(dx: 9999, dy: 9999)
    }

    /// Generates an R8Unorm Metal SDF texture from a given string.
    public static func generateSDF(
        text: String,
        device: MTLDevice,
        width: Int = 512,
        height: Int = 256,
        spread: Float = 24.0
    ) -> TextSDFResult? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = cleanText.isEmpty ? "MYTH" : cleanText

        // 1. Render text into an 8-bit grayscale bitmap
        var rawPixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &rawPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Choose a high-impact bold monospaced or display font
        let fontCandidates = ["Impact", "HelveticaNeue-Bold", "Menlo-Bold", "SFPro-Black", "Arial-BoldMT"]
        var selectedFont = NSFont.boldSystemFont(ofSize: 100)
        for name in fontCandidates {
            if let f = NSFont(name: name, size: 100) {
                selectedFont = f
                break
            }
        }

        // Measure text size and scale font to fit comfortably within the bounds with padding
        let paddingX = CGFloat(width) * 0.12
        let paddingY = CGFloat(height) * 0.18
        let maxTextW = CGFloat(width) - paddingX * 2.0
        let maxTextH = CGFloat(height) - paddingY * 2.0

        let sampleAttrs: [NSAttributedString.Key: Any] = [.font: selectedFont]
        let sampleSize = (displayText as NSString).size(withAttributes: sampleAttrs)

        let scaleFactor = min(maxTextW / max(sampleSize.width, 1.0), maxTextH / max(sampleSize.height, 1.0))
        let targetFontSize = max(16.0, selectedFont.pointSize * scaleFactor)
        let finalFont = NSFont(name: selectedFont.fontName, size: targetFontSize) ?? selectedFont

        let finalAttrs: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: NSColor.white
        ]
        let measuredSize = (displayText as NSString).size(withAttributes: finalAttrs)

        let drawRect = CGRect(
            x: (CGFloat(width) - measuredSize.width) * 0.5,
            y: (CGFloat(height) - measuredSize.height) * 0.5,
            width: measuredSize.width,
            height: measuredSize.height
        )

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        (displayText as NSString).draw(in: drawRect, withAttributes: finalAttrs)
        NSGraphicsContext.restoreGraphicsState()

        // 2. Compute 8SSEDT (Signed Euclidean Distance Transform)
        var insideGrid = [GridPoint](repeating: .infinity, count: width * height)
        var outsideGrid = [GridPoint](repeating: .infinity, count: width * height)

        for y in 0..<height {
            let rowOffset = y * width
            for x in 0..<width {
                let isInside = rawPixels[rowOffset + x] > 127
                if isInside {
                    insideGrid[rowOffset + x] = GridPoint(dx: 0, dy: 0)
                } else {
                    outsideGrid[rowOffset + x] = GridPoint(dx: 0, dy: 0)
                }
            }
        }

        // Pass 1: Forward (top-to-bottom, left-to-right)
        runForwardPass(grid: &insideGrid, width: width, height: height)
        runForwardPass(grid: &outsideGrid, width: width, height: height)

        // Pass 2: Backward (bottom-to-top, right-to-left)
        runBackwardPass(grid: &insideGrid, width: width, height: height)
        runBackwardPass(grid: &outsideGrid, width: width, height: height)

        // 3. Combine into normalized Signed Distance Field (0..255)
        // 128 (0.5) represents the exact font surface contour.
        var sdfPixels = [UInt8](repeating: 0, count: width * height)
        let spreadVal = max(spread, 1.0)

        for i in 0..<(width * height) {
            let dIn = sqrt(Float(insideGrid[i].distSq))
            let dOut = sqrt(Float(outsideGrid[i].distSq))
            let signedDist = dIn - dOut // Negative inside, positive outside

            // Normalize so 0.5 is surface, > 0.5 is inside, < 0.5 is outside
            let normalized = 0.5 - (signedDist / (2.0 * spreadVal))
            let clamped = max(0.0, min(1.0, normalized))
            sdfPixels[i] = UInt8(clamped * 255.0)
        }

        // 4. Create Metal .r8Unorm texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: desc) else {
            return nil
        }

        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: &sdfPixels, bytesPerRow: width)

        // Compute 3D half-dimensions
        let aspect = Float(measuredSize.width / max(measuredSize.height, 1.0))
        let halfH: Float = 0.42
        let halfW: Float = min(1.45, max(0.5, halfH * aspect))

        return TextSDFResult(
            texture: texture,
            aspect: aspect,
            halfW: halfW,
            halfH: halfH
        )
    }

    private static func runForwardPass(grid: inout [GridPoint], width: Int, height: Int) {
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var p = grid[row + x]
                if p.distSq == 0 { continue }

                // Check left neighbor (x - 1, y)
                if x > 0 {
                    let neighbor = grid[row + (x - 1)]
                    let candidate = GridPoint(dx: neighbor.dx + 1, dy: neighbor.dy)
                    if candidate.distSq < p.distSq { p = candidate }
                }

                // Check top neighbors
                if y > 0 {
                    let prevRow = (y - 1) * width
                    // (x, y - 1)
                    let nTop = grid[prevRow + x]
                    let cTop = GridPoint(dx: nTop.dx, dy: nTop.dy + 1)
                    if cTop.distSq < p.distSq { p = cTop }

                    // (x - 1, y - 1)
                    if x > 0 {
                        let nTopLeft = grid[prevRow + (x - 1)]
                        let cTopLeft = GridPoint(dx: nTopLeft.dx + 1, dy: nTopLeft.dy + 1)
                        if cTopLeft.distSq < p.distSq { p = cTopLeft }
                    }

                    // (x + 1, y - 1)
                    if x + 1 < width {
                        let nTopRight = grid[prevRow + (x + 1)]
                        let cTopRight = GridPoint(dx: nTopRight.dx - 1, dy: nTopRight.dy + 1)
                        if cTopRight.distSq < p.distSq { p = cTopRight }
                    }
                }

                grid[row + x] = p
            }
        }
    }

    private static func runBackwardPass(grid: inout [GridPoint], width: Int, height: Int) {
        for y in (0..<height).reversed() {
            let row = y * width
            for x in (0..<width).reversed() {
                var p = grid[row + x]
                if p.distSq == 0 { continue }

                // Check right neighbor (x + 1, y)
                if x + 1 < width {
                    let neighbor = grid[row + (x + 1)]
                    let candidate = GridPoint(dx: neighbor.dx - 1, dy: neighbor.dy)
                    if candidate.distSq < p.distSq { p = candidate }
                }

                // Check bottom neighbors
                if y + 1 < height {
                    let nextRow = (y + 1) * width
                    // (x, y + 1)
                    let nBottom = grid[nextRow + x]
                    let cBottom = GridPoint(dx: nBottom.dx, dy: nBottom.dy - 1)
                    if cBottom.distSq < p.distSq { p = cBottom }

                    // (x + 1, y + 1)
                    if x + 1 < width {
                        let nBottomRight = grid[nextRow + (x + 1)]
                        let cBottomRight = GridPoint(dx: nBottomRight.dx - 1, dy: nBottomRight.dy - 1)
                        if cBottomRight.distSq < p.distSq { p = cBottomRight }
                    }

                    // (x - 1, y + 1)
                    if x > 0 {
                        let nBottomLeft = grid[nextRow + (x - 1)]
                        let cBottomLeft = GridPoint(dx: nBottomLeft.dx + 1, dy: nBottomLeft.dy - 1)
                        if cBottomLeft.distSq < p.distSq { p = cBottomLeft }
                    }
                }

                grid[row + x] = p
            }
        }
    }
}
