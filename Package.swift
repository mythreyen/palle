// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Palle",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Palle", targets: ["Palle"])
    ],
    targets: [
        .executableTarget(
            name: "Palle",
            path: "Sources/Palle",
            exclude: ["Shaders/ASCIIShaders.metal"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
