# Palle ⚡️

> Dynamic 3D Text, Number, and ASCII Art Wallpaper Engine for macOS

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![Metal](https://img.shields.io/badge/Rendered%20with-Apple%20Metal-blue?logo=apple)](https://developer.apple.com/metal/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

I built Palle as a personal Mac wallpaper that renders real time 3D scenes into interactive ASCII art using Apple Metal. I created this niche tool for myself to keep it lightweight and battery friendly, but loved having it on my desktop so much that I wanted to share it with everyone who appreciates retro terminal art and creative coding.

---

## ✨ Features

* **⚡ Cell-Center Quantized 3D Raymarching:** Fuses 3D signed-distance field (SDF) evaluation and glyph texturing into a single render pass with 100% thread coherency across Apple Silicon GPU cores.
* **🔬 Real-Time Detail & Resolution Scaling:** Switch live between 4 resolution presets:
  * **Ultra-High Detail (9pt):** 25,000+ simultaneous glyph cells capturing fine curves and thin rings.
  * **High Detail (12pt):** Balanced high-definition contours and smooth gradients.
  * **Standard ASCII (16pt):** Classic retro terminal density.
  * **Retro Chunky (22pt):** Bold cyberpunk character blocks.
* **💡 Cinematic 3D Lighting Engine:** 4-tap cone-traced Ambient Occlusion (AO), Blinn-Phong specular glints, chromatic Fresnel rim lighting, and gamma-mapped tone curves.
* **🎨 Runtime CoreText Font Atlas:** Single-channel grayscale `.r8Unorm` texture strip generated on the fly at true Retina pixel scale in under 2ms.
* **🖱️ Interactive Mouse Parallax:** Procedural 3D perspective tilt that tracks cursor movement across your screen without stealing window focus or intercepting clicks.
* **🔋 3-Tier Battery & Power Guard:**
  * **Desktop Occlusion Detection:** Automatically pauses rendering (0.0% GPU usage) whenever standard application windows cover 92% or more of the screen.
  * **Low Power Mode Adaptation:** Steps down frame rates from 60 FPS to 24 FPS automatically when battery saver is engaged.
  * **Display Sleep Hook:** Freezes render loops the moment your display sleeps or the lid closes.
* **🖥️ Multi-Monitor Desktop Layer Integration:** Renders smoothly behind Finder desktop icons (`kCGDesktopWindowLevelKey`), supporting drag-selection, right-clicks, and Mission Control Spaces without Dock icon clutter.

---

## 🌌 3D Scenes & Animations

1. **⚡️ 3D MYTH Cyber Hologram:** Floating extruded 3D monogram with inner beveled neon grooves, 32-tick laser-engraved astrolabe gyro-rings, and dual orbiting plasma beacons.
2. **🌌 3D MYTH Cosmic Wormhole:** Relativistic Kerr black hole with Doppler-brightened accretion disk, photon sphere ring, and floating central crest.
3. **🎄 3D Christmas Tree & Snow:** 4-tier pine canopy with needle displacement, grooved trunk, 8-point faceted star topper, and real-time drifting snowflakes.
4. **🌀 Cyber Warp Tunnel:** Retro-futuristic hyperspace tunnel with undulating walls, longitudinal speed tracks, and glowing acceleration ribs.
5. **💎 Pulsing Gyroid Crystal:** Multi-scale harmonic fractal gyroid minimal surface blooming inside a faceted sphere.
6. **🧬 3D Double Helix:** Rotating DNA molecule with major and minor grooves connected by periodic base-pair ladder rungs.
7. **3D Torus Knot:** Dual interlocking tori with sinusoidal surface micro-displacement.
8. **Topological Number Wave:** Flowing multi-frequency trigonometric wave matrix.
9. **Morphing Octahedron:** Smooth geometric interpolation between an octahedron and sphere.

---

## 🎨 Palettes & Color Themes

### Character Palettes
* `⚡️ MYTH Cyber Stream`: ` MYTHmyth0123456789::*#@`
* `👑 Pure MYTH Typography`: ` MYTH`
* `❄️ Holiday Snow & Stars`: ` .·*+oO#@▲★❄`
* `🎄 Festive ASCII Art`: ` .*+o8#@^~|`
* `Classic ASCII Density`: ` .:-=+*#%@`
* `3D Number Grid`: ` 0123456789`
* `Binary Stream`: ` 01`
* `Hexadecimal Telemetry`: ` 0123456789ABCDEF`
* `Cyberpunk Matrix`: ` 012345789Z:.*+=<>|¦`

### Color Themes
* **Mythic Amethyst & Gold:** Royal violet backdrop with imperial cyber-gold glyphs.
* **Mythic Crimson Cyber:** Deep midnight obsidian with electric neon crimson highlights.
* **Matrix Mint:** Classic terminal green on deep carbon black.
* **Amber CRT:** Warm vintage amber phosphor glow.
* **Cyber Cyan:** Neon electric cyan on midnight blue.
* **Holiday Evergreen:** Vibrant pine green on deep cranberry mahogany.
* **Winter Frost:** Glacial ice blue on polar midnight.
* **Neon Sunset:** Synthwave hot magenta on dark violet.
* **Monochrome Paper:** Minimalist monochrome newspaper contrast.

---

## 🚀 Quick Start & Build Instructions

### Prerequisites
* A Mac running **macOS 13.0 (Ventura)** or newer.
* **Xcode Command Line Tools** (`xcode-select --install`).

### Option A: Run Directly from Terminal
```bash
git clone https://github.com/mythreyen/palle.git
cd palle
swift run -c release
```

Look at the top-right macOS Menu Bar for the **`MYTH::3D`** icon to switch scenes, detail resolutions, palettes, and themes in real time.

### Option B: Build Standalone `Palle.app` Bundle
```bash
chmod +x Scripts/build_app_bundle.sh
./Scripts/build_app_bundle.sh
open build/Palle.app
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
