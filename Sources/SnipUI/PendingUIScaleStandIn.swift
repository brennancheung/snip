import AppKit

// STAND-IN for #2236's Interface size setting (PR #12), which isn't on main yet. Delete this file
// when rebasing onto main after #2236 lands. It has the same shape as #2236's `UIScale` for what
// DonePanel uses (`current`, `metric(_:)`, `font(_:weight:)`), but `current` is fixed at 2×.
struct UIScale: Equatable, Sendable {
    let factor: CGFloat

    @MainActor static var current: UIScale { UIScale(factor: 2) }

    func metric(_ base: CGFloat) -> CGFloat {
        base * factor
    }

    func font(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: metric(base), weight: weight)
    }
}
