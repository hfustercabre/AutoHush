import SwiftUI

/// macOS's own switch (the user, 2026-10-17), the same in the menu and in
/// Settings, at macOS's own size.
struct PillToggleStyle: ToggleStyle {
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
    /// The highlight's corners, unfilled (a push button draws its own).
    var cornerRadius: CGFloat = 8

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if filled && isSelected {
            Button(configuration).buttonStyle(.borderedProminent)
                .modifier(HighlightableControl(cornerRadius: 6, press: configuration.trigger))
        } else if filled {
            Button(configuration).buttonStyle(.bordered)
                .modifier(HighlightableControl(cornerRadius: 6, press: configuration.trigger))
        } else {
            Button(configuration).buttonStyle(HoverHighlight(cornerRadius: cornerRadius))
                .modifier(HighlightableControl(cornerRadius: cornerRadius, press: configuration.trigger))
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
        @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

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
            // In the menu and Settings, `HighlightableControl` lights it in the accent color instead.
            return isHovered && keyboard == nil ? AnyShapeStyle(.chipHoverFill) : AnyShapeStyle(.clear)
        }
    }
}

extension PrimitiveButtonStyle where Self == ChipButtonStyle {
    /// A push button, the look of Settings' buttons.
    static var chip: ChipButtonStyle { ChipButtonStyle(filled: true) }
}

/// In the menu and Settings (wherever a `KeyHighlight` is given), a control
/// that the arrow keys and the pointer highlight and the keyboard's focus
/// reaches, all three shown by a faint tint of the system's accent color
/// behind it (F5, the user's pick, 2026-10-18; under the pointer too, the
/// user: "the accent color should show not only on keyboard navigation, but
/// also when the mouse is over the item"), instead of macOS's focus ring.
/// For a control that is itself focusable (a button, a switch); a row that
/// holds one uses `Highlightable` with its control's focus. In a row that
/// takes the highlight for its control (`Highlightable.ownsControls`), only
/// its focus shows. Elsewhere, macOS's ring stays.
struct HighlightableControl: ViewModifier {
    var cornerRadius: CGFloat = 8
    /// How far in from the control's sides the tint is drawn.
    var inset: CGFloat = 0
    /// How far out around a control that fills its own frame (a switch).
    var outset: CGFloat = 0
    /// Kept on: a row whose side window is open.
    var isLit = false
    /// A row that lights up by itself (`MenuRowButtonStyle`), as a menu
    /// item, instead of the tint (`showsKeyHighlight`).
    var lightsItself = false
    /// What Return or Space does while it's highlighted.
    let press: (() -> Void)?
    var opensSide = false
    @FocusState private var isFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.isInHighlightedRow) private var isInHighlightedRow

    @ViewBuilder func body(content: Content) -> some View {
        if keyboard == nil {
            content
        } else if isInHighlightedRow {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .background { HighlightTint(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset).padding(-outset) }
        } else {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .modifier(Highlightable(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset, outset: outset,
                                        isLit: isLit, lightsItself: lightsItself, press: press, opensSide: opensSide))
        }
    }
}

/// In the menu and Settings (wherever a `KeyHighlight` is given), a row or
/// a control the highlight goes to: it registers where it is and what
/// pressing it (or ← and →) does, the pointer moves the highlight onto it,
/// and the tint shows behind it while it's highlighted, has the keyboard's
/// focus (`isFocused`, its control's) or `isLit`; a dimmed one is skipped.
/// `lightsItself`: no tint, the view shows it itself (`showsKeyHighlight`:
/// a menu item's row, the card). `ownsControls`: a row whose one button
/// takes no highlight of its own (Settings' rows, the user's pick: the
/// whole row). Elsewhere, nothing.
struct Highlightable: ViewModifier {
    var isFocused = false
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0
    var outset: CGFloat = 0
    var isLit = false
    var lightsItself = false
    /// Whether it can be changed now, beyond the environment's `isEnabled`.
    var isAvailable = true
    var ownsControls = false
    var press: (() -> Void)?
    var adjust: ((Int) -> Void)?
    var opensSide = false
    var isCurrent: (() -> Bool)?
    @State private var id = UUID()
    @State private var actions = Actions()
    @Environment(\.isEnabled) private var isEnabled
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    /// What pressing it does as it was drawn last: registered once, its
    /// closures stay those of the latest drawing.
    @MainActor private final class Actions {
        var press: (() -> Void)?
        var adjust: ((Int) -> Void)?
        var isCurrent: (() -> Bool)?
    }

    @ViewBuilder func body(content: Content) -> some View {
        if let keyboard {
            let enabled = isEnabled && isAvailable
            let _ = { actions.press = press; actions.adjust = adjust; actions.isCurrent = isCurrent }()
            let lit = isFocused || isLit || (enabled && keyboard.highlighted == id)
            content
                .environment(\.showsKeyHighlight, lightsItself && lit)
                .environment(\.isInHighlightedRow, ownsControls)
                .background {
                    HighlightTint(isFocused: !lightsItself && lit, cornerRadius: cornerRadius, inset: inset)
                        .padding(-outset)
                }
                .id(id)
                .onHover { keyboard.hover(id, $0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { keyboard.update(id, frame: $0) }
                .onAppear {
                    let actions = actions
                    keyboard.register(id, .init(isEnabled: enabled,
                                                press: press == nil ? nil : { actions.press?() },
                                                adjust: adjust == nil ? nil : { actions.adjust?($0) },
                                                opensSide: opensSide,
                                                isCurrent: isCurrent == nil ? nil : { actions.isCurrent?() == true }))
                }
                .onChange(of: enabled) { keyboard.update(id, isEnabled: enabled) }
                .onDisappear { keyboard.remove(id) }
        } else {
            content
        }
    }
}

extension View {
    /// A row of Settings (or the menu) as `Highlightable`, its tint 6 pt out
    /// to its sides and 3 pt above and below it, as the menu's rows.
    func highlightableRow(isFocused: Bool = false, ownsControls: Bool = false,
                          press: (() -> Void)? = nil, adjust: ((Int) -> Void)? = nil) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 3)
            .modifier(Highlightable(isFocused: isFocused, ownsControls: ownsControls, press: press, adjust: adjust))
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
    }
}

/// The tint itself (`focusTint`), behind a control or a row that is
/// highlighted or has the keyboard's focus.
struct HighlightTint: View {
    let isFocused: Bool
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0
    var fill: Color = .focusTint

    var body: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .padding(.horizontal, inset)
                .allowsHitTesting(false)
        }
    }
}
