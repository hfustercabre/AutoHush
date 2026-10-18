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
                .modifier(MenuFocusTint(cornerRadius: 6, press: configuration.trigger))
        } else if filled {
            Button(configuration).buttonStyle(.bordered)
                .modifier(MenuFocusTint(cornerRadius: 6, press: configuration.trigger))
        } else {
            Button(configuration).buttonStyle(HoverHighlight(cornerRadius: cornerRadius))
                .modifier(MenuFocusTint(cornerRadius: cornerRadius, press: configuration.trigger))
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
        @Environment(\.isInMenu) private var isInMenu

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
            // In the menu, `MenuFocusTint` lights it in the accent color instead.
            return isHovered && !isInMenu ? AnyShapeStyle(.chipHoverFill) : AnyShapeStyle(.clear)
        }
    }
}

extension PrimitiveButtonStyle where Self == ChipButtonStyle {
    /// A push button, the look of Settings' buttons.
    static var chip: ChipButtonStyle { ChipButtonStyle(filled: true) }
}

/// In the menu, a control that the arrow keys and the pointer highlight
/// (`MenuKeyboard`) and the keyboard's focus reaches, all three shown by a
/// faint tint of the system's accent color behind it (F5, the user's pick,
/// 2026-10-18; under the pointer too, the user: "the accent color should
/// show not only on keyboard navigation, but also when the mouse is over
/// the item"), instead of macOS's focus ring. For a control that is itself
/// focusable (a button, a switch); a row that holds one uses
/// `MenuHighlight` with its control's focus. Outside the menu, macOS's ring
/// stays.
struct MenuFocusTint: ViewModifier {
    var cornerRadius: CGFloat = 8
    /// How far in from the control's sides the tint is drawn.
    var inset: CGFloat = 0
    /// How far out around a control that fills its own frame (a switch).
    var outset: CGFloat = 0
    /// Kept on: a row whose side window is open.
    var isLit = false
    /// A row that lights up by itself (`MenuRowButtonStyle`), as a menu
    /// item, instead of the tint (`isMenuHighlighted`).
    var lightsItself = false
    /// What Return or Space does while it's highlighted.
    let press: (() -> Void)?
    var opensSide = false
    @FocusState private var isFocused: Bool
    @Environment(\.isInMenu) private var isInMenu

    @ViewBuilder func body(content: Content) -> some View {
        if isInMenu {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .modifier(MenuHighlight(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset, outset: outset,
                                        isLit: isLit, lightsItself: lightsItself, press: press, opensSide: opensSide))
        } else {
            content
        }
    }
}

/// In the menu, a row or a control `MenuKeyboard` highlights: it registers
/// where it is and what pressing it (or ← and →) does, the pointer moves the
/// highlight onto it, and the tint shows behind it while it's highlighted,
/// has the keyboard's focus (`isFocused`, its control's) or `isLit`; a
/// dimmed one is skipped. `lightsItself`: no tint, the view shows it itself
/// (`isMenuHighlighted`: a menu item's row, the card). Outside the menu,
/// nothing.
struct MenuHighlight: ViewModifier {
    var isFocused = false
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0
    var outset: CGFloat = 0
    var isLit = false
    var lightsItself = false
    /// Whether it can be changed now, beyond the environment's `isEnabled`.
    var isAvailable = true
    var press: (() -> Void)?
    var adjust: ((Int) -> Void)?
    var opensSide = false
    @State private var id = UUID()
    @State private var actions = Actions()
    @Environment(\.isInMenu) private var isInMenu
    @Environment(\.isEnabled) private var isEnabled
    @Environment(MenuKeyboard.self) private var keyboard: MenuKeyboard?

    /// What pressing it does as it was drawn last: registered once, its
    /// closures stay those of the latest drawing.
    @MainActor private final class Actions {
        var press: (() -> Void)?
        var adjust: ((Int) -> Void)?
    }

    @ViewBuilder func body(content: Content) -> some View {
        if isInMenu {
            let enabled = isEnabled && isAvailable
            let _ = { actions.press = press; actions.adjust = adjust }()
            let lit = isFocused || isLit || (enabled && keyboard?.highlighted == id)
            content
                .environment(\.isMenuHighlighted, lightsItself && lit)
                .background {
                    MenuFocusBackground(isFocused: !lightsItself && lit, cornerRadius: cornerRadius, inset: inset)
                        .padding(-outset)
                }
                .id(id)
                .onHover { keyboard?.hover(id, $0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { keyboard?.update(id, frame: $0) }
                .onAppear {
                    let actions = actions
                    keyboard?.register(id, .init(isEnabled: enabled,
                                                 press: press == nil ? nil : { actions.press?() },
                                                 adjust: adjust == nil ? nil : { actions.adjust?($0) },
                                                 opensSide: opensSide))
                }
                .onChange(of: enabled) { keyboard?.update(id, isEnabled: enabled) }
                .onDisappear { keyboard?.remove(id) }
        } else {
            content
        }
    }
}

/// The tint itself (`focusTint`), behind a control or a row that is
/// highlighted or has the keyboard's focus.
struct MenuFocusBackground: View {
    let isFocused: Bool
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0

    var body: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.focusTint)
                .padding(.horizontal, inset)
                .allowsHitTesting(false)
        }
    }
}
