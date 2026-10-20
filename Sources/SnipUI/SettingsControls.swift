import AppKit
import SwiftUI

// AppKit controls for the Settings window. SwiftUI's segmented pickers, popups and bordered
// buttons draw their text at the system size whatever `.font` says; these set the font themselves.

/// A segmented control (one choice of a few) with its labels at `fontSize`.
struct SegmentedControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    var options: [(label: String, value: Value)]
    var fontSize: CGFloat

    func makeCoordinator() -> ControlAction { ControlAction() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.target = context.coordinator
        control.action = #selector(ControlAction.fire(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.handler = { sender in
            let index = (sender as? NSSegmentedControl)?.selectedSegment ?? -1
            if options.indices.contains(index) { selection = options[index].value }
        }
        control.controlSize = NSControl.ControlSize(context.environment.controlSize)
        control.font = .systemFont(ofSize: fontSize)
        control.segmentCount = options.count
        for (index, option) in options.enumerated() {
            control.setLabel(option.label, forSegment: index)
            control.setWidth(0, forSegment: index)  // fit the label
        }
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
        control.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// A popup menu with its title and items at `fontSize`.
struct PopUpControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    var options: [(label: String, value: Value)]
    var fontSize: CGFloat

    func makeCoordinator() -> ControlAction { ControlAction() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = context.coordinator
        popup.action = #selector(ControlAction.fire(_:))
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.handler = { sender in
            let index = (sender as? NSPopUpButton)?.indexOfSelectedItem ?? -1
            if options.indices.contains(index) { selection = options[index].value }
        }
        popup.controlSize = NSControl.ControlSize(context.environment.controlSize)
        let font = NSFont.systemFont(ofSize: fontSize)
        popup.font = font
        popup.menu?.font = font
        let titles = options.map(\.label)
        if popup.itemArray.map(\.title) != titles {
            // Items one by one: addItems(withTitles:) drops duplicate names, e.g. two "USB Audio".
            popup.removeAllItems()
            for title in titles {
                popup.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
        }
        popup.selectItem(at: options.firstIndex { $0.value == selection } ?? -1)
        popup.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// A push button with its title at `fontSize`.
struct PushButton: NSViewRepresentable {
    var title: String
    var fontSize: CGFloat
    var action: () -> Void

    func makeCoordinator() -> ControlAction { ControlAction() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .push
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(ControlAction.fire(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.handler = { _ in action() }
        button.controlSize = NSControl.ControlSize(context.environment.controlSize)
        button.attributedTitle = NSAttributedString.controlTitle(title, font: .systemFont(ofSize: fontSize))
        button.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// The target of an AppKit control's action; calls `handler`.
@MainActor
final class ControlAction: NSObject {
    var handler: (NSControl) -> Void = { _ in }

    @objc func fire(_ sender: NSControl) { handler(sender) }
}

extension NSControl.ControlSize {
    /// AppKit's size for SwiftUI's. AppKit's .extraLarge needs macOS 26 (the package targets 15),
    /// so SwiftUI's .extraLarge becomes .large.
    init(_ size: SwiftUI.ControlSize) {
        switch size {
        case .mini: self = .mini
        case .small: self = .small
        case .large, .extraLarge: self = .large
        default: self = .regular
        }
    }
}

extension NSAttributedString {
    /// A centred button title in `font`. A button's plain `font` doesn't always hold, this does.
    static func controlTitle(_ title: String, font: NSFont) -> NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        return NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: NSColor.controlTextColor,
            .paragraphStyle: centred,
        ])
    }
}

/// A Settings row: the label on the left, vertically centred on the control on the right.
struct CentredRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            configuration.label
                .layoutPriority(1)
            Spacer(minLength: 0)
            configuration.content
        }
    }
}
