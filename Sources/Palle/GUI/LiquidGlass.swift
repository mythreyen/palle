import Cocoa
import SwiftUI

// MARK: - Native macOS Visual Effect Blur
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Liquid Glass Panel Modifier
public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var isSelected: Bool
    public var accentColor: Color?
    public var isHovered: Bool

    public init(
        cornerRadius: CGFloat = 12,
        isSelected: Bool = false,
        accentColor: Color? = nil,
        isHovered: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.isSelected = isSelected
        self.accentColor = accentColor
        self.isHovered = isHovered
    }

    public func body(content: Content) -> some View {
        let activeAccent = accentColor ?? Color.accentColor

        content
            .background(
                ZStack {
                    // Optical blur base
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Liquid glass tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [activeAccent.opacity(0.18), activeAccent.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(isHovered ? 0.08 : 0.04), Color.white.opacity(0.01)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )

                    // Specular glass highlight reflection (top curved sheen)
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(isHovered ? 0.22 : 0.14), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        Spacer()
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [activeAccent, activeAccent.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.40 : 0.25),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(isHovered ? 0.20 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? activeAccent.opacity(0.35)
                    : Color.black.opacity(isHovered ? 0.25 : 0.15),
                radius: isSelected ? 12 : (isHovered ? 10 : 6),
                x: 0,
                y: isHovered ? 4 : 2
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 12,
        isSelected: Bool = false,
        accentColor: Color? = nil,
        isHovered: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            isSelected: isSelected,
            accentColor: accentColor,
            isHovered: isHovered
        ))
    }
}

// MARK: - Liquid Glass Badge Capsule
public struct LiquidGlassBadge: View {
    public let icon: String?
    public let text: String
    public var accentColor: Color?

    public init(icon: String? = nil, text: String, accentColor: Color? = nil) {
        self.icon = icon
        self.text = text
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(accentColor ?? .primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Color SIMD4 Extension
public extension Color {
    init(simd4: SIMD4<Float>) {
        self.init(
            red: Double(simd4.x),
            green: Double(simd4.y),
            blue: Double(simd4.z),
            opacity: Double(simd4.w)
        )
    }
}

