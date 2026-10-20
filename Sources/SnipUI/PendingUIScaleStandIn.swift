import AppKit

// STAND-IN for #2236's Interface size setting, which isn't on main yet. Delete this file when
// rebasing onto main after #2236 lands. DonePanel uses only `UIScale.font(_:weight:)` and
// `UIScale.metric(_:)`; the real ones read `effectiveInterfaceScale` from the settings.
@MainActor
enum UIScale {
    private static let scale: CGFloat = 2.0

    static func font(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: base * scale, weight: weight)
    }

    static func metric(_ base: CGFloat) -> CGFloat {
        (base * scale).rounded()
    }
}
