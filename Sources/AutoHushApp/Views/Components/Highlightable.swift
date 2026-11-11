import AppKit
import SwiftUI

/// In the menu and Settings (wherever a `KeyHighlight` is given), a row or
/// a control the highlight goes to: it registers where it is and what
/// pressing it (or ← and →) does, the pointer moves the highlight onto it,
/// and the tint shows behind it while it's highlighted, has the keyboard's
/// focus (`isFocused`, its control's; unless something was highlighted
/// since, K9) or `isLit`; a dimmed one is skipped, unless it has a reason
/// to show (`HighlightReason`, A13a).
/// A key moving the highlight onto it moves VoiceOver's cursor there too
/// (`KeyHighlight.Light.arrivals`), so VoiceOver says what's lit, once:
/// nothing is announced besides (A3, 2026-11-01); VoiceOver's cursor moved
/// onto it by VoiceOver's own keys brings the highlight (K5, 2026-11-10).
/// It tells the highlight when it has the keyboard's focus, which the keys
/// then go on from (`KeyHighlight.focused`, W9).
/// `lightsItself`: no tint behind it, the view draws it itself
/// (`showsKeyHighlight`: a menu item's row, the card). `ownsControls`: a row whose one button
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
    var select: (() -> Void)?
    var adjust: ((Int) -> Void)?
    var opensSide = false
    var isCurrent: (() -> Bool)?
    /// Only Tab and Shift-Tab stop on it (`KeyHighlight.Control.tabOnly`).
    var tabOnly = false
    /// What ↑ and ↓ do on it, a list that's one stop (`KeyHighlight.Control.scroll`).
    var scroll: ((Int) -> Bool)? = nil
    /// Where VoiceOver's cursor goes as a key lights it, instead of onto
    /// the whole of it: in a view of several elements, the control its
    /// press changes (the menu's card: its Auto-Pause switch, where
    /// VoiceOver took the first, the player's name; N11, the a11y audit,
    /// 2026-11-06).
    var voiceOverTarget: AccessibilityFocusState<Bool>.Binding? = nil
    /// What VoiceOver says as a key lights it, after its cursor moves
    /// there: a pop-up's name and choice, which VoiceOver doesn't say on
    /// its own once its cursor is moved onto one (the a11y round 2's
    /// leftovers, 2026-11-06). `nil`: nothing besides.
    var arrivalSpeech: (() -> String?)? = nil
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
    @Environment(\.voiceOver) private var voiceOver

    /// What pressing it does as it was drawn last: registered once, its
    /// closures stay those of the latest drawing (they may hold what it
    /// drew: an order, a permission).
    @MainActor private final class Actions {
        var press: (() -> Void)?
        var select: (() -> Void)?
        var adjust: ((Int) -> Void)?
        var delete: (() -> Void)?
        var isCurrent: (() -> Bool)?
        var scroll: ((Int) -> Bool)?
        var arrivalSpeech: (() -> String?)?
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
            // The keyboard's focus (a click's, with keyboard navigation on) is the keys' too.
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
                // VoiceOver's own keys moved its cursor here: the highlight
                // follows (K5); on the arrival above, it's here already.
                // SwiftUI says so only at VoiceOver's next move: right after
                // `VoiceOverCursor` told it at once, this is left out, and
                // without Accessibility always (`VoiceOverCursor` follows the
                // focus then).
                .onChange(of: hasVoiceOverCursor || voiceOverTarget?.wrappedValue == true) { _, hasCursor in
                    guard hasCursor, voiceOver.isOn() else { return }
                    if VoiceOverCursor.shared.takesLateReport() {
                        keyboard.followVoiceOver(to: id)
                    } else if !VoiceOverCursor.shared.watches() {
                        keyboard.voiceOverMoved()
                    }
                }
                .onChange(of: isFocused, initial: true) { keyboard.focus(id, isFocused) }
                .onChange(of: keyboard.light(id).arrivals) {
                    // Only for VoiceOver: without it, nothing to move.
                    guard voiceOver.isOn() else { return }
                    if let voiceOverTarget { voiceOverTarget.wrappedValue = true } else { hasVoiceOverCursor = true }
                    if let speech = actions.arrivalSpeech?() { postStepAnnouncement(speech) }
                }
                .onHover { keyboard.hover(id, $0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { keyboard.update(id, frame: $0) }
                .onAppear {
                    let actions = actions
                    keyboard.register(id, .init(band: band, group: group, isEnabled: enabled, explains: reason != nil,
                                                press: press == nil ? nil : { actions.press?() },
                                                select: select == nil ? nil : { actions.select?() },
                                                adjust: adjust == nil ? nil : { actions.adjust?($0) },
                                                delete: removal == nil ? nil : { actions.delete?() },
                                                opensSide: opensSide,
                                                isCurrent: isCurrent == nil ? nil : { actions.isCurrent?() == true },
                                                tabOnly: tabOnly,
                                                scroll: scroll == nil ? nil : { actions.scroll?($0) ?? false }))
                }
                .onChange(of: enabled) { keyboard.update(id, isEnabled: enabled) }
                // A reason that comes or goes while it stays (Option held in the players).
                .onChange(of: reason != nil) { keyboard.update(id, explains: reason != nil) }
                .onChange(of: lit) { removal?.lit(lit) }
                .onChange(of: Drawing(), initial: true) {
                    actions.press = press
                    actions.select = select
                    actions.adjust = adjust
                    actions.delete = removal?.remove
                    actions.isCurrent = isCurrent
                    actions.scroll = scroll
                    actions.arrivalSpeech = arrivalSpeech
                }
                .onDisappear { keyboard.remove(id) }
        } else {
            content
        }
    }
}

extension View {
    /// A click anywhere in a row's tint (`highlightableRow`'s 6 and 3 pt
    /// around it) does what one on its control does; the control takes its
    /// own clicks (the user, 2026-11-03 and 2026-11-05).
    func clickAnywhere(_ action: @escaping () -> Void) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
    }

    /// A row of Settings (or the menu) as `Highlightable`, its tint out of
    /// its layout, `horizontal` pt to its sides and `vertical` pt above and
    /// below it: 6 and 3, as the menu's rows, unless it says otherwise.
    /// `voiceOverTarget`: the row's control VoiceOver stops on (its switch,
    /// slider, pop-up or button), so VoiceOver's cursor there brings the
    /// highlight (K5-1, 2026-11-10: on a switch row it stayed on the row
    /// before), and a key's arrival moves VoiceOver's cursor onto it.
    func highlightableRow(isFocused: Bool = false, isAvailable: Bool = true, ownsControls: Bool = false,
                          cornerRadius: CGFloat = 8, horizontal: CGFloat = 6, vertical: CGFloat = 3,
                          press: (() -> Void)? = nil, select: (() -> Void)? = nil, adjust: ((Int) -> Void)? = nil,
                          isCurrent: (() -> Bool)? = nil, arrivalSpeech: (() -> String?)? = nil,
                          voiceOverTarget: AccessibilityFocusState<Bool>.Binding? = nil) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .modifier(Highlightable(isFocused: isFocused, cornerRadius: cornerRadius, isAvailable: isAvailable,
                                    ownsControls: ownsControls, press: press, select: select, adjust: adjust,
                                    isCurrent: isCurrent, voiceOverTarget: voiceOverTarget, arrivalSpeech: arrivalSpeech))
            .padding(.horizontal, -horizontal)
            .padding(.vertical, -vertical)
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

/// What Delete does on a highlighted control that can be removed (an added
/// app's tile), and what it's told as the highlight comes and goes, for its
/// × to show (the workflow audit, 2026-10-22).
struct HighlightRemoval {
    let remove: () -> Void
    let lit: (Bool) -> Void
}
