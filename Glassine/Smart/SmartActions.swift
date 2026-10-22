import AppKit

/// What happens with results of the smart tools: copy to the clipboard and say so in the HUD.
@MainActor
enum SmartActions {
    /// Recognizes the text in `image` and copies it.
    static func copyText(from image: CGImage) {
        // Stays up until the result replaces it; the first run after launch loads Vision's models.
        HUD.show("Reading text…", symbol: "text.viewfinder", autoHide: false)
        let start = ContinuousClock.now
        Task {
            do {
                let text = try await TextRecognizer.recognize(image)
                let (seconds, attoseconds) = (ContinuousClock.now - start).components
                let ms = Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
                Log.capture.notice("Text recognized in \(ms, privacy: .public) ms (\(image.width, privacy: .public)×\(image.height, privacy: .public) px)")
                present(text)
            } catch {
                HUD.hide()
                Alerts.present(error)
            }
        }
    }

    static func present(_ text: String) {
        guard !text.isEmpty else {
            HUD.show("No text found", detail: "Try selecting a larger or sharper area.", symbol: "text.magnifyingglass")
            return
        }
        copy(text)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        HUD.show(lines == 1 ? "Text copied" : "Text copied · \(lines) lines", detail: text, symbol: "text.viewfinder")
    }

    static func copyColor(_ color: NSColor) {
        let text = color.formatted(Preferences.colorFormat)
        copy(text)
        HUD.show("Color copied", detail: text, swatch: color)
    }

    static func copyMeasurement(_ text: String) {
        copy(text)
        HUD.show("Measurement copied", detail: text, symbol: "ruler")
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
