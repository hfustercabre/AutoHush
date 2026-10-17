import SwiftUI

/// macOS's own switch (the user, 2026-10-17), the same in the menu and in
/// Settings. `width` and `height` are kept for callers; macOS sizes it.
struct PillToggleStyle: ToggleStyle {
    var width: CGFloat = 36
    var height: CGFloat = 21

    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label }
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

/// A button in macOS's own styles (the user, 2026-10-17): filled, a push
/// button (`.bordered`), prominent while selected (the main button, the
/// chosen chip); unfilled, a plain label that lights up under the pointer,
/// like the menu's rows (the menu's toolbar, the players' tiles).
struct ChipButtonStyle: PrimitiveButtonStyle {
    var filled = false
    var isSelected = false
    var cornerRadius: CGFloat = 8
    /// Kept for callers: a push button makes its own room.
    var padded = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if filled && isSelected {
            Button(configuration).buttonStyle(.borderedProminent)
        } else if filled {
            Button(configuration).buttonStyle(.bordered)
        } else {
            Button(configuration).buttonStyle(HoverHighlight(cornerRadius: cornerRadius))
        }
    }

    /// A label that lights up under the pointer, and a step more while pressed.
    private struct HoverHighlight: ButtonStyle {
        let cornerRadius: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            Lit(label: configuration.label, isPressed: configuration.isPressed, cornerRadius: cornerRadius)
        }
    }

    private struct Lit<Label: View>: View {
        let label: Label
        let isPressed: Bool
        let cornerRadius: CGFloat
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(.primary)
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }

        private var fill: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(.clear) }
            if isPressed { return AnyShapeStyle(.tertiary) }
            return isHovered ? AnyShapeStyle(.chipHoverFill) : AnyShapeStyle(.clear)
        }
    }
}

extension PrimitiveButtonStyle where Self == ChipButtonStyle {
    /// A push button, the look of Settings' buttons.
    static var chip: ChipButtonStyle { ChipButtonStyle(filled: true, padded: true) }
}
