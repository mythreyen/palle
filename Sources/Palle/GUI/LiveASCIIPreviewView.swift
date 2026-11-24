import Cocoa
import Metal
import MetalKit
import SwiftUI

/// High-performance lightweight SwiftUI wrapper for rendering a live mini 3D ASCII viewport.
public struct LiveASCIIPreviewView: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return mtkView }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 30 // Balanced 30 FPS for thumbnail preview (cuts GPU draw by 50%)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = ASCIIRenderer(mtkView: mtkView) {
            mtkView.delegate = renderer
            context.coordinator.renderer = renderer
        }

        context.coordinator.attach(mtkView: mtkView)
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
        weak var mtkView: MTKView?
        private var observers: [Any] = []

        func attach(mtkView: MTKView) {
            self.mtkView = mtkView

            let obsHide = NotificationCenter.default.addObserver(
                forName: StudioWindowManager.didHideWindowNotification,
                object: nil,
                queue: .main
            ) { [weak mtkView] _ in
                mtkView?.isPaused = true
            }

            let obsShow = NotificationCenter.default.addObserver(
                forName: StudioWindowManager.didShowWindowNotification,
                object: nil,
                queue: .main
            ) { [weak mtkView] _ in
                mtkView?.isPaused = false
            }

            observers = [obsHide, obsShow]
        }

        deinit {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }
}
