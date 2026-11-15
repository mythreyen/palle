import Cocoa
import Metal

public final class CustomTextManager {
    public static let shared = CustomTextManager()

    private let userDefaultsKey = "PalleCustom3DText"

    private init() {}

    /// Restores or generates initial 3D text SDF on application launch
    public func restoreSavedTextIfAny(device: MTLDevice) {
        let savedText = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "MYTH"
        _ = updateCustomText(savedText, device: device)
    }

    /// Generates the 3D SDF texture for the new text string and updates WallpaperConfig
    public func updateCustomText(_ text: String, device: MTLDevice) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeText = trimmed.isEmpty ? "MYTH" : trimmed

        guard let result = TextSDFGenerator.generateSDF(text: activeText, device: device) else {
            NSLog("[Palle] Failed to generate 3D text SDF for: \(activeText)")
            return false
        }

        let config = WallpaperConfig.shared
        config.custom3DText = activeText
        config.textSDFTexture = result.texture
        config.textAspect = result.aspect
        config.textHalfW = result.halfW
        config.textHalfH = result.halfH
        config.hasCustomTextSDF = true

        UserDefaults.standard.set(activeText, forKey: userDefaultsKey)
        NSLog("[Palle] Updated 3D Hologram Text to: \"\(activeText)\" (aspect: \(String(format: "%.2f", result.aspect)))")
        return true
    }

    /// Resets 3D text to default "MYTH"
    public func resetToDefault(device: MTLDevice) {
        _ = updateCustomText("MYTH", device: device)
    }

    /// Displays an interactive macOS alert modal for setting custom 3D text
    public func promptForCustomText(device: MTLDevice, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Set 3D Hologram Text"
            alert.informativeText = "Type any word, name, or slogan to extrude in real-time within the 3D cyber holographic astrolabe and cosmic wormhole."
            alert.alertStyle = .informational

            alert.addButton(withTitle: "Update Hologram")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Reset to MYTH")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
            textField.stringValue = WallpaperConfig.shared.custom3DText
            textField.placeholderString = "e.g. PALLE, CYBER, NEO, 2026"
            textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
            alert.accessoryView = textField

            NSApp.activate(ignoringOtherApps: true)
            alert.window.initialFirstResponder = textField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let success = self.updateCustomText(textField.stringValue, device: device)
                completion(success)
            } else if response == .alertThirdButtonReturn {
                self.resetToDefault(device: device)
                completion(true)
            } else {
                completion(false)
            }
        }
    }
}
