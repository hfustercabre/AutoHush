import SwiftUI

/// A switch drawn in the accent color, the same in the menu and in Settings.
/// The system's switch would be grey in the menu: menus draw it inactive,
/// since AutoHush doesn't become the active app when its menu opens.
struct PillToggleStyle: ToggleStyle {
    var width: CGFloat = 36
    var height: CGFloat = 21

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.switchOffFill))
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
/// Filled, it's a chip, as for the menu's duration buttons and Settings'
/// buttons; selected, it's filled with the accent color. On macOS 26 and
/// later a filled chip is Liquid Glass (tinted with the accent color when
/// selected); a button's chip (`padded`) is then a capsule.
struct ChipButtonStyle: ButtonStyle {
    var filled = false
    var isSelected = false
    var cornerRadius: CGFloat = 8
    /// Room around a plain label, such as a text button's title; off for
    /// labels that make their own.
    var padded = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *), filled {
            GlassChip(isSelected: isSelected, shape: padded ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))) {
                configuration.label
                    .padding(.horizontal, padded ? 14 : 0)
                    .padding(.vertical, padded ? 6 : 0)
            }
        } else {
            HoverHighlight(isPressed: configuration.isPressed, filled: filled, isSelected: isSelected, cornerRadius: cornerRadius) {
                configuration.label
                    .padding(.horizontal, padded ? 12 : 0)
                    .padding(.vertical, padded ? 5 : 0)
            }
        }
    }

    /// A filled chip as Liquid Glass, which lights up under the pointer and
    /// when pressed by itself (`interactive`).
    @available(macOS 26, *)
    private struct GlassChip<Label: View>: View {
        let isSelected: Bool
        let shape: AnyShape
        @ViewBuilder let label: Label
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .glassEffect(isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }

    private struct HoverHighlight<Label: View>: View {
        let isPressed: Bool
        let filled: Bool
        let isSelected: Bool
        let cornerRadius: CGFloat
        @ViewBuilder let label: Label
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }

        private var fill: AnyShapeStyle {
            if isSelected { return AnyShapeStyle(Color.accentColor.opacity(isPressed ? 0.8 : 1)) }
            guard isEnabled else { return filled ? AnyShapeStyle(.chipFill) : AnyShapeStyle(.clear) }
            if isPressed { return AnyShapeStyle(.tertiary) }
            if isHovered { return AnyShapeStyle(.chipHoverFill) }
            return filled ? AnyShapeStyle(.chipFill) : AnyShapeStyle(.clear)
        }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    /// A filled chip, the look of Settings' buttons.
    static var chip: ChipButtonStyle { ChipButtonStyle(filled: true, padded: true) }
}
