import AppKit
import SwiftUI

/// In the menu and Settings (wherever a `KeyHighlight` is given), a control
/// that the arrow keys and the pointer highlight and the keyboard's focus
/// reaches, all three shown by a faint tint of the system's accent color
/// behind it (F5, the user's pick, 2026-10-18; under the pointer too, the
/// user: "the accent color should show not only on keyboard navigation, but
/// also when the mouse is over the item"), instead of macOS's focus ring;
/// outlined where the keys put it (`HighlightTint`).
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
    /// A ring `outset` out, not the tint behind it: a filled control
    /// (`HighlightTint.ring`).
    var ring = false
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
        if let keyboard, isInHighlightedRow {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .background {
                    HighlightTint(isFocused: isFocused && !keyboard.hidesFocus, byKeys: true, cornerRadius: cornerRadius, inset: inset,
                                  ring: ring)
                        .padding(-outset)
                }
        } else if keyboard == nil {
            content
        } else {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .modifier(Highlightable(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset, outset: outset, ring: ring,
                                        isLit: isLit, lightsItself: lightsItself, press: press, opensSide: opensSide))
        }
    }
}

/// In the menu and Settings (wherever a `KeyHighlight` is given), a row or
/// a control the highlight goes to: it registers where it is and what
/// pressing it (or ← and →) does, the pointer moves the highlight onto it,
/// and the tint shows behind it while it's highlighted, has the keyboard's
/// focus (`isFocused`, its control's; unless something was highlighted
/// since, K9) or `isLit`; a dimmed one is skipped, unless it has a reason
/// to show (`HighlightReason`, A13a).
/// A key moving the highlight onto it moves VoiceOver's cursor there too
/// (`KeyHighlight.Light.arrivals`), so VoiceOver says what's lit, once:
/// nothing is announced besides (A3, 2026-11-01).
/// `lightsItself`: no tint, the view shows it itself (`showsKeyHighlight`:
/// a menu item's row, the card). `ownsControls`: a row whose one button
/// takes no highlight of its own (Settings' rows, the user's pick: the
/// whole row). Elsewhere, nothing.
struct Highlightable: ViewModifier {
    var isFocused = false
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0
    var outset: CGFloat = 0
    var ring = false
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
    @AccessibilityFocusState private var hasVoiceOverCursor: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.highlightBand) private var band
    @Environment(\.highlightRemoval) private var removal
    @Environment(\.highlightGroup) private var group
    @Environment(\.highlightReason) private var reason
    @Environment(\.highlightRevealRoom) private var revealRoom
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
            let light = keyboard.light(id)
            let isOn = keyboard.shows(id, isEnabled: enabled)
            let focusShows = isFocused && !keyboard.hidesFocus
            let lit = focusShows || isLit || isOn
            // Tab's focus is the keys' too.
            let byKeys = focusShows || (isOn && light.byKeys)
            content
                .environment(\.showsKeyHighlight, lightsItself && lit)
                .environment(\.keyHighlightByKeys, byKeys)
                .environment(\.isInHighlightedRow, ownsControls)
                .environment(\.highlightReason, nil)
                .background {
                    HighlightTint(isFocused: !lightsItself && lit, byKeys: byKeys, cornerRadius: cornerRadius, inset: inset, ring: ring)
                        .padding(-outset)
                }
                .preference(key: ShownHighlightReason.self, value: byKeys ? reason : nil)
                // What the keys scroll into view (`RevealsKeyHighlight`): it,
                // and the room under it that a fade at the bottom takes.
                .padding(.bottom, revealRoom)
                .id(id)
                .padding(.bottom, -revealRoom)
                .accessibilityFocused($hasVoiceOverCursor)
                .onChange(of: keyboard.light(id).arrivals) {
                    // Only for VoiceOver: without it, nothing to move.
                    if NSWorkspace.shared.isVoiceOverEnabled { hasVoiceOverCursor = true }
                }
                .onHover { keyboard.hover(id, $0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { keyboard.update(id, frame: $0) }
                .onAppear {
                    let actions = actions
                    keyboard.register(id, .init(band: band, group: group, isEnabled: enabled, explains: reason != nil,
                                                press: press == nil ? nil : { actions.press?() },
                                                adjust: adjust == nil ? nil : { actions.adjust?($0) },
                                                delete: removal == nil ? nil : { actions.delete?() },
                                                opensSide: opensSide,
                                                isCurrent: isCurrent == nil ? nil : { actions.isCurrent?() == true }))
                }
                .onChange(of: enabled) { keyboard.update(id, isEnabled: enabled) }
                // A reason that comes or goes while it stays (Option held in the players).
                .onChange(of: reason != nil) { keyboard.update(id, explains: reason != nil) }
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
/// highlighted or has the keyboard's focus; outlined in the accent color
/// (2 pt) where the keys put it, so it shows at 3:1, and always with
/// Increase Contrast (A2a, 2026-11-01). Under the pointer, the tint alone.
/// `ring`: around a filled control (a prominent button), which hides what's
/// behind it, the outline alone, drawn out of it as macOS's focus ring
/// (P1, the user's pick, 2026-11-02); nothing under the pointer.
struct HighlightTint: View {
    let isFocused: Bool
    var byKeys = false
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0
    var ring = false
    var fill: Color = .focusTint
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if isFocused, ring {
            if byKeys || contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        } else if isFocused {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(fill)
                .overlay {
                    if byKeys || contrast == .increased { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
                }
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
    /// The menu's highlight (`KeyHighlight`) or the keyboard's focus is on
    /// this view, which shows it itself (`Highlightable.lightsItself`): a
    /// menu item's row lights up, the menu's card takes the tint over its
    /// glass.
    @Entry var showsKeyHighlight = false
    /// Inside a row that takes the highlight for its one button
    /// (`Highlightable.ownsControls`): the button shows only its focus.
    @Entry var isInHighlightedRow = false
    /// The keys (or Tab) put the highlight on this view, not the pointer:
    /// the menu's card outlines its tint, a menu row shows its reason.
    @Entry var keyHighlightByKeys = false
    /// Set around a control (`highlightReason(_:)`): why it's dimmed, or
    /// what it does, shown while the keys' highlight is on it.
    @Entry var highlightReason: String?
    /// Room left under a control the keys scroll into view: a fade at the
    /// scroll view's bottom covers it (the welcome window's tiles, A4c).
    @Entry var highlightRevealRoom: CGFloat = 0
}

extension View {
    /// `reason` shows while the keys' highlight is on this control (A13a,
    /// the user's pick, 2026-11-01: what only a help tag said, for the
    /// keyboard); dimmed, the keys still stop on it for that. `nil`: none.
    /// Shown by a `HighlightReasonCaption` around it, or read inside it
    /// (`keyHighlightByKeys`, a menu row).
    func highlightReason(_ reason: String?) -> some View {
        environment(\.highlightReason, reason)
    }
}

/// The reason of the control the keys' highlight is on, from inside a view
/// (`highlightReason(_:)`).
struct ShownHighlightReason: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = value ?? nextValue()
    }
}

/// `text` as a caption while the keys' highlight is on the row it's in
/// (A13a): what a row's control does, which its help tag says to the pointer.
struct KeyHighlightCaption: View {
    let text: String
    @Environment(\.keyHighlightByKeys) private var byKeys

    var body: some View {
        if byKeys { Text(verbatim: text).captionStyle() }
    }
}

/// `content`, then the reason of the control in it the keys' highlight is
/// on, if any, as a caption under it (A13a).
struct HighlightReasonCaption<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if let reason { Text(verbatim: reason).captionStyle() }
        }
        .onPreferenceChange(ShownHighlightReason.self) { shown in
            MainActor.assumeIsolated { reason = shown }
        }
    }
}

/// What Delete does on a highlighted control that can be removed (an added
/// app's tile), and what it's told as the highlight comes and goes, for its
/// × to show (the workflow audit, 2026-10-22).
struct HighlightRemoval {
    let remove: () -> Void
    let lit: (Bool) -> Void
}

/// Scrolls the arrow keys' highlight into view as it moves
/// (`KeyHighlight.revealed`): every Settings page, About's too (R7, the full
/// check, 2026-10-27: written on each before), and what scrolls in the menu
/// and its side window (`MenuScrollArea`), which scroll without animating;
/// none does with Reduce Motion on (A11, 2026-11-01), as the menu's panel
/// and `ScrollDriver` don't. Its height is the highlight's page
/// (`MeasuresHighlightPage`).
struct RevealsKeyHighlight: ViewModifier {
    let scroller: ScrollViewProxy
    var animated = true
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    func body(content: Content) -> some View {
        content.measuresHighlightPage().onChange(of: keyboard?.revealed) { _, revealed in
            guard let revealed else { return }
            if animated, !reducesMotion {
                withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(revealed) }
            } else {
                scroller.scrollTo(revealed)
            }
        }
    }
}

/// What scrolls in a window with a highlight (`KeyHighlight`), its height
/// told as the highlight's page, for Page Up and Page Down
/// (`KeyHighlight.pageHeight`, 2026-11-01).
struct MeasuresHighlightPage: ViewModifier {
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { keyboard?.pageHeight = $0 }
    }
}

extension View {
    /// Tells the highlight how tall a page is (`MeasuresHighlightPage`).
    func measuresHighlightPage() -> some View {
        modifier(MeasuresHighlightPage())
    }

    /// Scrolls the arrow keys' highlight into view with `scroller` (`RevealsKeyHighlight`).
    func revealsKeyHighlight(with scroller: ScrollViewProxy, animated: Bool = true) -> some View {
        modifier(RevealsKeyHighlight(scroller: scroller, animated: animated))
    }
}
