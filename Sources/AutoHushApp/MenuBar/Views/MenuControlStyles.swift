import SwiftUI

/// The width of the menu's custom views; rows the menu draws itself follow.
let menuContentWidth: CGFloat = 320

/// A switch drawn in the accent color. Menus draw the system's switches as
/// inactive, in grey, since AutoHush never becomes the active app.
struct PillToggleStyle: ToggleStyle {
    var width: CGFloat = 36
    var height: CGFloat = 21

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                .frame(width: width, height: height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5).padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // VoiceOver gets a switch with its label.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A rounded button that lights up under the pointer, like the menu's rows.
struct MenuButtonStyle: ButtonStyle {
    /// Filled even when the pointer is elsewhere, as for the duration buttons.
    var filled = false
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(isPressed: configuration.isPressed, filled: filled, cornerRadius: cornerRadius) {
            configuration.label
        }
    }

    private struct HoverHighlight<Label: View>: View {
        let isPressed: Bool
        let filled: Bool
        let cornerRadius: CGFloat
        @ViewBuilder let label: Label
        @State private var isHovered = false

        var body: some View {
            label
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .onHover { isHovered = $0 }
        }

        private var fill: AnyShapeStyle {
            if isPressed { return AnyShapeStyle(.tertiary) }
            if isHovered { return AnyShapeStyle(.quaternary) }
            return filled ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear)
        }
    }
}

/// A small heading over a group of the menu's controls.
struct MenuSectionLabel: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title.font(.caption).foregroundStyle(.secondary)
    }
}
