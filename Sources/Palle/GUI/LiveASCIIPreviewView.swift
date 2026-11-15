import Cocoa
import Metal
import MetalKit
import SwiftUI

/// High-performance SwiftUI wrapper for rendering a live mini 3D ASCII viewport.
public struct LiveASCIIPreviewView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return mtkView }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = ASCIIRenderer(mtkView: mtkView) {
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        }

        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        // Automatically updates at display refresh rate
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        var renderer: ASCIIRenderer?
    }
}
