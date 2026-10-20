import AppKit
import SnipCore
import SwiftUI

/// How large Snip draws its own UI: the Interface size setting, resolved. Every size Snip sets
/// (fonts, paddings, corner radii, icons, panels) is a macOS-default base size run through this,
/// so 200% turns 13 pt body text into 26 pt. The menu bar menu is drawn by macOS and isn't scaled.
struct UIScale: Equatable, Sendable {
    /// 1 is the macOS default sizes.
    let factor: CGFloat

    init(_ factor: CGFloat) {
        self.factor = factor
    }

    /// The saved setting, resolved against the main display. Read it when building a view:
    /// it reflects a change saved through `SettingsStore` at once.
    @MainActor static var current: UIScale {
        UIScale(settings: SettingsStore.shared.settings)
    }

    @MainActor init(settings: RecordingSettings) {
        let display = Self.mainDisplay
        factor = settings.effectiveInterfaceScale(displayWidth: display.width, backingScale: display.backingScale)
    }

    /// What Automatic resolves to on this Mac's main display.
    @MainActor static var automaticFactor: CGFloat {
        let display = mainDisplay
        return RecordingSettings.automaticInterfaceScale(displayWidth: display.width, backingScale: display.backingScale)
    }

    /// The display with the menu bar, its width in points and backing scale.
    @MainActor private static var mainDisplay: (width: Double, backingScale: Double) {
        guard let screen = NSScreen.screens.first else { return (0, 2) }
        return (screen.frame.width, screen.backingScaleFactor)
    }

    /// A padding, corner radius, icon size, button height or panel size.
    func metric(_ base: CGFloat) -> CGFloat {
        base * factor
    }

    /// The system font at `base` points, scaled. 13 is body text, 11 small.
    func font(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: metric(base), weight: weight)
    }

    /// The system font with fixed-width digits, for sizes and times.
    func monospacedDigitFont(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: metric(base), weight: weight)
    }

    /// `font(_:weight:)` for SwiftUI.
    func text(_ base: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: metric(base), weight: weight)
    }

    /// "125%".
    static func percent(_ factor: Double) -> String {
        "\(Int((factor * 100).rounded()))%"
    }
}
