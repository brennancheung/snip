import AppKit
import SwiftUI

// The Settings window's controls, drawn by Snip at the interface size. AppKit's bezelled
// controls (and SwiftUI's, which are AppKit underneath) keep a fixed height for each control
// size whatever their font, so their text was tiny or clipped on a large 1x monitor. These
// size themselves from `UIScale`, text and bezel together.

/// The rounded bezel shared by Settings' buttons and popup; `BezelButton` is the AppKit twin.
struct BezelButtonStyle: ButtonStyle {
    var scale: UIScale

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: scale.metric(6), style: .continuous)
        configuration.label
            .padding(.horizontal, scale.metric(10))
            .padding(.vertical, scale.metric(4))
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
            .contentShape(shape)
    }
}

/// A push button with its title at body size.
struct PushButton: View {
    var title: String
    var scale: UIScale
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(scale.text(13))
        }
        .buttonStyle(BezelButtonStyle(scale: scale))
    }
}

/// A segmented control: one choice of a few, the chosen one filled with the accent colour.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(label: String, value: Value)]
    var scale: UIScale

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: scale.metric(7), style: .continuous)
        HStack(spacing: scale.metric(2)) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(scale.metric(2))
        .background(outer.fill(Color.primary.opacity(0.08)))
        .overlay(outer.strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }

    private func segment(_ option: (label: String, value: Value)) -> some View {
        let chosen = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.label)
                .font(scale.text(13, weight: chosen ? .medium : .regular))
                .foregroundStyle(chosen ? Color.white : Color.primary)
                .padding(.horizontal, scale.metric(10))
                .padding(.vertical, scale.metric(3))
                .frame(minWidth: scale.metric(34))
                .background(
                    RoundedRectangle(cornerRadius: scale.metric(5), style: .continuous)
                        .fill(chosen ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A popup: the chosen option and a chevron in a bezel; clicking opens a menu of the options,
/// its items at the same size.
struct PopUpControl<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(label: String, value: Value)]
    var scale: UIScale
    @State private var anchor = MenuAnchor()

    var body: some View {
        let chosen = options.firstIndex { $0.value == selection }
        Button {
            anchor.popUp(titles: options.map(\.label), chosen: chosen, font: scale.font(13)) { index in
                if options.indices.contains(index) { selection = options[index].value }
            }
        } label: {
            HStack(spacing: scale.metric(8)) {
                Text(chosen.map { options[$0].label } ?? "")
                    .font(scale.text(13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(scale.text(9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(BezelButtonStyle(scale: scale))
        .background(MenuAnchorView(anchor: anchor))
    }
}

/// Opens a popup's menu over the AppKit view behind it.
@MainActor
final class MenuAnchor: NSObject {
    weak var view: NSView?
    private var onPick: (Int) -> Void = { _ in }

    func popUp(titles: [String], chosen: Int?, font: NSFont, onPick: @escaping (Int) -> Void) {
        guard let view else { return }
        self.onPick = onPick
        let menu = NSMenu()
        menu.font = font
        menu.autoenablesItems = false
        menu.minimumWidth = view.bounds.width
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(picked(_:)), keyEquivalent: "")
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
            item.target = self
            item.tag = index
            item.state = index == chosen ? .on : .off
            menu.addItem(item)
        }
        // The chosen item over the button, as a popup button does.
        let item = chosen.flatMap { menu.items.indices.contains($0) ? menu.items[$0] : nil }
        let top = view.isFlipped ? 0 : view.bounds.height
        menu.popUp(positioning: item, at: NSPoint(x: 0, y: top), in: view)
    }

    @objc private func picked(_ item: NSMenuItem) { onPick(item.tag) }
}

/// A plain NSView the size of the popup, so its menu can open in the right place.
private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// A switch, drawn at the interface size.
struct ScaledSwitch<Label: View>: View {
    @Binding var isOn: Bool
    var scale: UIScale
    /// What VoiceOver reads it as.
    var label: Label

    var body: some View {
        let inset = scale.metric(2)
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.18))
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: scale.metric(1), y: scale.metric(0.5))
                    .padding(inset)
            }
            .frame(width: scale.metric(36), height: scale.metric(20))
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
            }
            .accessibilityRepresentation {
                Toggle(isOn: $isOn) { label }
            }
    }
}

/// A slider with a round knob and the filled part of the track in the accent colour.
/// Arrow keys step it once it has focus.
struct ScaledSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var scale: UIScale

    var body: some View {
        let knob = scale.metric(20)
        GeometryReader { geometry in
            let usable = max(geometry.size.width - knob, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span : 0
            let track = scale.metric(4)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: usable, height: track)
                    .offset(x: knob / 2)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: usable * fraction, height: track)
                    .offset(x: knob / 2)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: scale.metric(1.5), y: scale.metric(0.5))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: knob, height: knob)
                    .offset(x: usable * fraction)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                set(range.lowerBound + Double((drag.location.x - knob / 2) / usable) * span)
            })
        }
        .frame(height: knob + scale.metric(4))
        .frame(minWidth: scale.metric(120))
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: set(value - step)
            default: set(value + step)
            }
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step)
        }
    }

    /// `newValue` rounded to a step and kept in range.
    private func set(_ newValue: Double) {
        let stepped = step > 0 ? ((newValue - range.lowerBound) / step).rounded() * step + range.lowerBound : newValue
        let clamped = min(max(stepped, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
    }
}

/// A Settings row: the label on the left, vertically centred on the control on the right.
struct CentredRowStyle: LabeledContentStyle {
    var scale: UIScale

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: scale.metric(12)) {
            configuration.label
                .layoutPriority(1)
            Spacer(minLength: 0)
            configuration.content
        }
    }
}

/// A Settings switch row: the label on the left, vertically centred on the switch on the right.
struct CentredSwitchStyle: ToggleStyle {
    var scale: UIScale

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: scale.metric(12)) {
            configuration.label
                .layoutPriority(1)
            Spacer(minLength: 0)
            ScaledSwitch(isOn: configuration.$isOn, scale: scale, label: configuration.label)
        }
    }
}
