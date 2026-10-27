import SwiftUI

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
    @Environment(\.highlightBand) private var band
    @Environment(\.highlightRemoval) private var removal
    @Environment(\.highlightGroup) private var group
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    /// What pressing it does as it was drawn last: registered once, its
    /// closures stay those of the latest drawing (they may hold what it
    /// drew: an order, a permission).
    @MainActor private final class Actions {
        var press: (() -> Void)?
        var adjust: ((Int) -> Void)?
        var delete: (() -> Void)?
        var isCurrent: (() -> Bool)?
    }

    /// A drawing of it, unlike any other: each hands its closures over once
    /// it's done (`onChange`), not while it's drawn (U17, the full check,
    /// 2026-10-19: a view's body changes nothing).
    private struct Drawing: Equatable {
        let id = UUID()
    }

    @ViewBuilder func body(content: Content) -> some View {
        if let keyboard {
            let enabled = isEnabled && isAvailable
            // Its own light: a move redraws the controls it concerns only.
            let lit = isFocused || isLit || (enabled && keyboard.light(id).isOn)
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
                    keyboard.register(id, .init(band: band, group: group, isEnabled: enabled,
                                                press: press == nil ? nil : { actions.press?() },
                                                adjust: adjust == nil ? nil : { actions.adjust?($0) },
                                                delete: removal == nil ? nil : { actions.delete?() },
                                                opensSide: opensSide,
                                                isCurrent: isCurrent == nil ? nil : { actions.isCurrent?() == true }))
                }
                .onChange(of: enabled) { keyboard.update(id, isEnabled: enabled) }
                .onChange(of: lit) { removal?.lit(lit) }
                .onChange(of: Drawing(), initial: true) {
                    actions.press = press
                    actions.adjust = adjust
                    actions.delete = removal?.remove
                    actions.isCurrent = isCurrent
                }
                .onDisappear { keyboard.remove(id) }
        } else {
            content
        }
    }
}

extension View {
    /// A row of Settings (or the menu) as `Highlightable`, its tint out of
    /// its layout, `horizontal` pt to its sides and `vertical` pt above and
    /// below it: 6 and 3, as the menu's rows, unless it says otherwise.
    func highlightableRow(isFocused: Bool = false, isAvailable: Bool = true, ownsControls: Bool = false,
                          cornerRadius: CGFloat = 8, horizontal: CGFloat = 6, vertical: CGFloat = 3,
                          press: (() -> Void)? = nil, adjust: ((Int) -> Void)? = nil,
                          isCurrent: (() -> Bool)? = nil) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .modifier(Highlightable(isFocused: isFocused, cornerRadius: cornerRadius, isAvailable: isAvailable,
                                    ownsControls: ownsControls, press: press, adjust: adjust, isCurrent: isCurrent))
            .padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
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

extension EnvironmentValues {
    /// The part of its window a highlightable control is in (`HighlightBand`):
    /// set on the menu's card and buttons, and Sound Sources' heading and
    /// buttons, around what scrolls between them.
    @Entry var highlightBand = HighlightBand.middle
    /// Set around a control Delete removes (an added app's tile).
    @Entry var highlightRemoval: HighlightRemoval?
    /// The card a highlightable control is in (`Card`), so the highlight can
    /// go to the card's first row (`KeyHighlight.highlightFirst(in:)`).
    @Entry var highlightGroup: UUID?
}

/// What Delete does on a highlighted control that can be removed (an added
/// app's tile), and what it's told as the highlight comes and goes, for its
/// × to show (the workflow audit, 2026-10-22).
struct HighlightRemoval {
    let remove: () -> Void
    let lit: (Bool) -> Void
}
