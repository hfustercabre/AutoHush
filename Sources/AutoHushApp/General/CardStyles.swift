import SwiftUI

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
/// Filled, it's a chip, as for the menu's duration buttons and Settings'
/// buttons; selected, it's filled with the accent color.
struct ChipButtonStyle: ButtonStyle {
    var filled = false
    var isSelected = false
    var cornerRadius: CGFloat = 8
    /// Room around a plain label, such as a text button's title; off for
    /// labels that make their own.
    var padded = false

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(isPressed: configuration.isPressed, filled: filled, isSelected: isSelected, cornerRadius: cornerRadius) {
            configuration.label
                .padding(.horizontal, padded ? 12 : 0)
                .padding(.vertical, padded ? 5 : 0)
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
            guard isEnabled else { return filled ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear) }
            if isPressed { return AnyShapeStyle(.tertiary) }
            if isHovered { return AnyShapeStyle(.quaternary) }
            return filled ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear)
        }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    /// A filled chip, the look of Settings' buttons.
    static var chip: ChipButtonStyle { ChipButtonStyle(filled: true, padded: true) }
}

/// A small heading over a group of controls: a card, or the menu's buttons.
struct SectionLabel: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title.font(.caption).foregroundStyle(.secondary)
    }
}

/// A group of controls on a rounded, tinted background: the menu's card,
/// and each group in Settings.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.6)))
    }
}

/// The line between two rows of a card.
struct CardDivider: View {
    var body: some View {
        Divider().opacity(0.5)
    }
}

/// A title, an optional description under it, and a switch.
struct SwitchRow: View {
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool

    init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(title, subtitle: subtitle)
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { title }
                .toggleStyle(PillToggleStyle())
        }
    }
}

/// A row's title, with an optional description under it.
struct RowTitle: View {
    let title: Text
    var subtitle: Text?

    init(_ title: Text, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            if let subtitle {
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One choice among a few, as a row of chips; the chosen one is filled with
/// the accent color. An option can be unavailable: dimmed and not chosen,
/// but a click on it is reported, so the view can say why.
struct ChoiceChips<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
        var isAvailable = true
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void
    /// A click on an unavailable option.
    var onUnavailableClick: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    option.isAvailable ? onSelect(option.value) : onUnavailableClick()
                } label: {
                    Text(verbatim: option.title)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: option.value == selection))
                .opacity(option.isAvailable ? 1 : 0.45)
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
