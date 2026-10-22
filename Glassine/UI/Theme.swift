import AppKit
import SwiftUI

/// The accent: buttons, toggles, selection. Red is not an accent — it means recording.
enum AccentChoice: String, CaseIterable, Identifiable {
    case system, ink, sage, stamp, ochre

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .ink: "Ink"
        case .sage: "Sage"
        case .stamp: "Stamp"
        case .ochre: "Ochre"
        }
    }

    /// Ink when macOS is set to Multicolor ("let each app decide"); the system accent when the
    /// user picked a color there, since that is a choice of theirs.
    static func `default`(systemAccentChosen: Bool) -> AccentChoice {
        systemAccentChosen ? .system : .ink
    }
}

/// Glassine's look, shared by every window: the accent and whether the paper details
/// (perforation, grain, dots) are drawn. SwiftUI views read it from the environment
/// (`.themed()` at each window's root); AppKit views use `Theme.shared`. Colors and type come
/// from the generated asset catalog (`Color.ink`, `NSColor.paper`) and `Typography`.
@MainActor
@Observable
final class Theme {
    static let shared = Theme()

    var accentChoice: AccentChoice {
        didSet { UserDefaults.standard.set(accentChoice.rawValue, forKey: PrefKey.accent) }
    }

    /// Off with Increase Contrast or Reduce Transparency: texture there only gets in the way.
    private(set) var showsPaperDetails = true

    /// Bumped when macOS changes its accent color, so views showing it redraw.
    private var systemColorsRevision = 0

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let defaults = UserDefaults.standard
        accentChoice = defaults.string(forKey: PrefKey.accent).flatMap(AccentChoice.init(rawValue:))
            // AppleAccentColor is set only when a specific color is picked in System Settings.
            ?? .default(systemAccentChosen: defaults.object(forKey: "AppleAccentColor") != nil)
        updatePaperDetails()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePaperDetails() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemColorsRevision += 1 }
        })
    }

    private func updatePaperDetails() {
        let workspace = NSWorkspace.shared
        showsPaperDetails = !(workspace.accessibilityDisplayShouldIncreaseContrast
            || workspace.accessibilityDisplayShouldReduceTransparency)
    }

    // MARK: Accent

    var accent: Color { Color(nsColor: nsAccent) }
    var onAccent: Color { Color(nsColor: nsOnAccent) }

    var nsAccent: NSColor {
        switch accentChoice {
        case .system:
            _ = systemColorsRevision
            return .controlAccentColor
        case .ink: return .accentInk
        case .sage: return .accentSage
        case .stamp: return .accentStamp
        case .ochre: return .accentOchre
        }
    }

    /// Text and icons on the accent.
    var nsOnAccent: NSColor {
        switch accentChoice {
        case .system:
            _ = systemColorsRevision
            return Self.textColor(on: .controlAccentColor)
        case .ink: return .onAccentInk
        case .sage: return .onAccentSage
        case .stamp: return .onAccentStamp
        case .ochre: return .onAccentOchre
        }
    }

    /// Dark ink or white, whichever reads better on `fill`. The ink is the light theme's in both
    /// themes: a light accent needs dark text whatever the appearance.
    static func textColor(on fill: NSColor) -> NSColor {
        guard let rgb = Contrast.RGB(fill), let ink = Contrast.RGB(darkInk) else { return .white }
        return Contrast.prefersDarkText(on: rgb, dark: ink) ? darkInk : .white
    }

    private static let darkInk = NSColor(srgbRed: 0x1C / 255, green: 0x22 / 255, blue: 0x30 / 255, alpha: 1)
}

extension Contrast.RGB {
    /// The color's sRGB components; dynamic colors resolve in the current appearance.
    init?(_ color: NSColor) {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }
}

extension View {
    /// Puts Glassine's theme into a window's SwiftUI content: the environment and the accent tint.
    func themed() -> some View {
        ThemedRoot(content: self)
    }
}

private struct ThemedRoot<Content: View>: View {
    let content: Content
    private let theme = Theme.shared

    var body: some View {
        content
            .environment(theme)
            .tint(theme.accent)
    }
}
