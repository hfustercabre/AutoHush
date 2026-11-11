import AppKit
import CoreGraphics
import Foundation
import Observation

/// The highlight the arrow keys and the pointer move, as macOS's own menus
/// have one whatever the keyboard navigation setting (the user, 2026-10-18:
/// "Arrows, as menus"; Settings too: "Lets add the same over and arrows
/// navigation system to the Settings Window"): ↑ and ↓ move it row by row
/// in reading order, wrapping at the ends, and ← and → along a row of
/// several (the durations, the buttons, tiles); Return or Space presses the
/// one it's on; ← and → change a slider or a choice, and → opens a side
/// window. Tab and Shift-Tab move it control by control, a row's as the
/// language reads (`step`, `tabOrder`), stopping on the controls the
/// arrows go past too (`Control.tabOnly`: a search's ✕). Page Up and Page Down move it about a page, Home and End to the
/// first and last row (`jump`). The pointer moves it too, as in a menu: the
/// control under it is the highlighted one. Moved by a key, VoiceOver's
/// cursor and Zoom go with it (`Light.arrivals`, `screenFrame`); moved by
/// VoiceOver, it follows VoiceOver's cursor (`followFocus`, or SwiftUI's
/// late report through `followVoiceOver`). While
/// nothing is highlighted, the keys go on from the control the keyboard's
/// focus is on (`focused`). Each control registers itself (`Highlightable`)
/// with where it is and what pressing it does. The menu, its side window,
/// Settings' sidebar and Settings' page have one each.
@MainActor
@Observable
final class KeyHighlight {
    /// One of the controls, as it registered.
    struct Control {
        /// Where it is, in its window.
        var frame: CGRect = .zero
        /// The part of its window it's in, top to bottom (`HighlightBand`):
        /// the keys go part by part, so rows a scrolling middle hides never
        /// mix with the buttons pinned under it.
        var band = HighlightBand.middle
        /// The card it's in (`Card`), if any.
        var group: UUID?
        /// A dimmed one is skipped, unless it `explains` itself.
        var isEnabled = true
        /// Dimmed, it still takes the keys' highlight, to show why it's
        /// dimmed (`HighlightReason`, A13a, 2026-11-01); pressing it does nothing.
        var explains = false
        var press: (() -> Void)?
        /// What Space does instead of `press`, where the two differ: a list's
        /// row, selected (Sound Sources, the user, 2026-11-03: Return
        /// switches it, Space selects it).
        var select: (() -> Void)?
        /// ← (-1) or → (1): a slider's step, a choice's next option.
        var adjust: ((Int) -> Void)?
        /// What Delete does: removes it (an added app's tile), once confirmed.
        var delete: (() -> Void)?
        /// Pressing it opens a side window, which → does too.
        var opensSide = false
        /// It stands for what's shown now (Settings' sidebar: the page's row).
        var isCurrent: (() -> Bool)?
        /// Only Tab and Shift-Tab stop on it; ↑ and ↓, ← and →, Page Up,
        /// Page Down, Home and End go past it, as before it took the
        /// highlight (a search's ✕, which Tab reaches, B: the arrows go as
        /// before, 2026-11-10).
        var tabOnly = false
        /// ↑ (-1) or ↓ (1) scrolls it, a list that's one stop (the logs'
        /// entries); `false` at that end, where the arrows go on to the
        /// next row. The keys' stop only: the pointer never takes it
        /// (`innermostHovered`).
        var scroll: ((Int) -> Bool)?
    }

    /// The control the arrow keys or the pointer moved to.
    private(set) var highlighted: UUID? {
        didSet {
            guard highlighted != oldValue else { return }
            if let oldValue { lights[oldValue]?.isOn = false }
            if let highlighted { light(highlighted).isOn = true }
            hidesFocusIfLit()
            partner?.hidesFocusIfLit()
        }
    }
    /// Whether the keyboard's focus (a click's, with keyboard navigation
    /// on) hides its tint: something is highlighted here or in `partner`,
    /// moved there after the focus (K9, 2026-11-01: one tint at a time,
    /// whichever moved last). Observed only by the control with the focus.
    private(set) var hidesFocus = false
    /// The other highlight of the same keys (Settings' sidebar and page, the
    /// menu and its side window): either one lit hides the focus.
    @ObservationIgnored weak var partner: KeyHighlight?
    /// The control the arrow keys moved to last, to scroll into view; the
    /// pointer's never needs it.
    private(set) var revealed: UUID?
    @ObservationIgnored private(set) var controls: [UUID: Control] = [:]
    /// Something is highlighted now, by the keys or the pointer: Settings
    /// takes it from the other side's highlight, one at a time.
    @ObservationIgnored var onHighlight: (() -> Void)?
    @ObservationIgnored var wantsFirst = false
    /// Frames that came before their control registered.
    @ObservationIgnored private var earlyFrames: [UUID: CGRect] = [:]
    /// The control the keyboard's focus is on (a click's or the window's
    /// own, with keyboard navigation on), as it tells (`focus(_:_:)`):
    /// while nothing is highlighted, ↑ ↓ and Tab go on from it, not from
    /// the top, so the focus and the highlight are one place (W9, the
    /// user, 2026-11-10: "One indicator at a time"). Kept by `clear()`:
    /// the focus is still there.
    @ObservationIgnored private(set) var focused: UUID?
    /// The controls the pointer is over now. One can be inside another (the
    /// menu card's Change Player row in the card): the innermost is
    /// highlighted, and leaving it gives the highlight back to the one
    /// around it (the user, 2026-10-26: the card lost its tint once the
    /// pointer had been on the row).
    @ObservationIgnored private var hovered: [UUID] = []
    /// Each control's own "highlighted", so a move redraws the two controls
    /// it concerns, not every one (the full check, 2026-10-18).
    @ObservationIgnored private var lights: [UUID: Light] = [:]
    /// The order (`rows`) as it was when the keys came onto a control that
    /// shows a reason (`Control.explains`): the next move from it goes by
    /// that order, as the reason's caption, shown under it only while the
    /// keys are on it, can move the controls beside it (N2, 2026-11-06:
    /// Reopen's moved Change… below it in Settings → General, and ↓ went
    /// back to Change…, round and round). Dropped once a control comes,
    /// goes, dims or explains itself anew.
    @ObservationIgnored private(set) var orderOnArrival: (id: UUID, rows: [[UUID]])?
    /// When a key last moved the highlight onto each control: the focus
    /// that VoiceOver moves after it is no move of VoiceOver's (`followFocus`).
    @ObservationIgnored private var arrivedAt: [UUID: ContinuousClock.Instant] = [:]
    /// The control `followFocus` lit, while the highlight is still the one it
    /// put there: it goes out with the focus (`focusGone`).
    @ObservationIgnored private var litByFocus: UUID?
    /// When the keys, VoiceOver or the focus last put the highlight where it
    /// is (`voiceOverMoved`).
    @ObservationIgnored private var litAt: ContinuousClock.Instant?

    /// Whether one control is highlighted, observed by that control alone.
    @MainActor @Observable final class Light {
        fileprivate(set) var isOn = false
        /// The keys moved it there, not the pointer: its tint is outlined
        /// (A2a, 2026-11-01), and a reason it has shows (`HighlightReason`).
        fileprivate(set) var byKeys = false
        /// How many times a key moved the highlight onto it: each time,
        /// VoiceOver's cursor goes to it (A3, 2026-11-01), not when the
        /// pointer does, as VoiceOver's own cursor doesn't follow the mouse.
        fileprivate(set) var arrivals = 0
    }

    /// Page Up or Page Down, Home or End (`HighlightKey.jump`).
    enum Jump { case pageUp, pageDown, first, last }

    /// How tall the part that scrolls shows (the menu's list, a Settings
    /// page), as its view reports it (`RevealsKeyHighlight`): Page Up and
    /// Page Down go about that far. `nil`: all of it shows (the sidebar).
    @ObservationIgnored var pageHeight: CGFloat?
    /// Where a frame in the controls' window is on the screen, in Zoom's
    /// coordinates (`ZoomFocus.screenRect`); set by the window's owner, so
    /// Zoom follows the keys (A3, 2026-11-01). `nil`: Zoom isn't told.
    @ObservationIgnored var screenFrame: (@MainActor (CGRect) -> CGRect?)? {
        // Placed on screen, it can follow VoiceOver's cursor at once (`VoiceOverCursor`).
        didSet { if screenFrame != nil { VoiceOverCursor.shared.follow(self) } }
    }
    /// The view its controls are drawn in (`place(in:)`): its window is the
    /// one VoiceOver's cursor must be in for the highlight to follow it.
    @ObservationIgnored private var screenView: (@MainActor () -> NSView?)?
    var window: NSWindow? { screenView?()?.window }

    /// Its controls are drawn in `view` (a hosting view, as SwiftUI's
    /// `.global` frames are its own): Zoom and VoiceOver's cursor follow.
    func place(in view: @escaping @MainActor () -> NSView?) {
        screenView = view
        screenFrame = { rect in view().flatMap { ZoomFocus.screenRect(of: rect, in: $0) } }
    }
    /// Tells Zoom where the highlight is now, if Zoom is on (tests replace it).
    @ObservationIgnored var zoom: @MainActor (CGRect) -> Void = ZoomFocus.follow
    /// Whether the app is laid out right to left (Arabic, Hebrew): Tab goes
    /// along a row that way (`tabOrder`); tests replace it.
    @ObservationIgnored var readsRightToLeft: @MainActor () -> Bool = { NSApp?.userInterfaceLayoutDirection == .rightToLeft }
    /// The pointer moves it (`hover`). Off in tests that check the keys'
    /// highlight on screen, so the real pointer, resting wherever their
    /// window opens, never moves it (the full check, 2026-11-06, T-5).
    @ObservationIgnored var followsPointer = true

    /// The control's own `Light`.
    func light(_ id: UUID) -> Light {
        if let light = lights[id] { return light }
        let light = Light()
        light.isOn = highlighted == id
        lights[id] = light
        return light
    }

    func register(_ id: UUID, _ control: Control) {
        var control = control
        // Its frame may have come first.
        if let frame = earlyFrames.removeValue(forKey: id), control.frame == .zero { control.frame = frame }
        controls[id] = control
        orderOnArrival = nil
        firstWhenReady()
    }

    /// Its new frame; one for a control not registered (yet) is kept until
    /// it is, never making one up (a frame reported as it goes).
    func update(_ id: UUID, frame: CGRect) {
        if controls[id] != nil { controls[id]?.frame = frame } else { earlyFrames[id] = frame }
        firstWhenReady()
    }

    /// A highlighted control dimmed, or gone, gives the highlight to the
    /// innermost other one still under the pointer (the card around the
    /// card's Try Again), as leaving it does; none, without one. One that
    /// `explains` itself keeps the keys' highlight.
    func update(_ id: UUID, isEnabled: Bool) {
        controls[id]?.isEnabled = isEnabled
        orderOnArrival = nil
        guard !isEnabled, highlighted == id else { return }
        if controls[id]?.explains == true, lights[id]?.byKeys == true { return }
        point(at: innermostHovered(excluding: id))
    }

    /// A reason to be dimmed came or went (`HighlightReason`) without the
    /// control drawn anew: the keys stop on it while it has one; dimmed
    /// and highlighted, it gives the highlight up once it has none, as
    /// `update(_:isEnabled:)` does.
    func update(_ id: UUID, explains: Bool) {
        controls[id]?.explains = explains
        orderOnArrival = nil
        guard !explains, highlighted == id, controls[id]?.isEnabled == false else { return }
        point(at: innermostHovered(excluding: id))
    }

    /// Whether `id` shows the highlight now: enabled, or dimmed but
    /// explaining itself to the keys.
    func shows(_ id: UUID, isEnabled: Bool) -> Bool {
        let light = light(id)
        guard light.isOn else { return false }
        return isEnabled || (controls[id]?.explains == true && light.byKeys)
    }

    func remove(_ id: UUID) {
        controls[id] = nil
        earlyFrames[id] = nil
        if focused == id { focused = nil }
        if litByFocus == id { litByFocus = nil }
        arrivedAt[id] = nil
        orderOnArrival = nil
        hovered.removeAll { $0 == id }
        if highlighted == id { point(at: innermostHovered()) }
        lights[id] = nil
    }

    /// The keyboard's focus came onto a control (`true`) or left it.
    func focus(_ id: UUID, _ isFocused: Bool) {
        if isFocused { focused = id } else if focused == id { focused = nil }
    }

    /// VoiceOver's cursor came onto a control (VoiceOver's own keys moved
    /// it): the highlight goes there too, so plain Return and Space act on
    /// what VoiceOver is on (K5, the user, 2026-11-10; M10, S17, W13 of the
    /// keyboard review). As the keys' (`Light.byKeys`), but VoiceOver's
    /// cursor isn't moved again nor anything said, and Zoom and the scroll
    /// are left to VoiceOver. Not onto a dimmed control that has no reason
    /// to show.
    func followVoiceOver(to id: UUID) {
        guard highlighted != id, let control = controls[id], control.isEnabled || control.explains else { return }
        orderOnArrival = control.explains ? (id, rows) : nil
        highlighted = id
        light(id).byKeys = true
        litAt = .now
        litByFocus = nil
        onHighlight?()
    }

    /// The keyboard's focus came onto a control while VoiceOver is on
    /// (`VoiceOverCursor`: Accessibility's notification, or, without it, its
    /// look): VoiceOver moved it there, so the highlight follows
    /// (`followVoiceOver`; D-1, the user's A, 2026-11-11; with Accessibility
    /// too since W-2). Not when it's the echo of a key's own arrival
    /// in the last second: the arrival moves VoiceOver's cursor, which moves
    /// the focus, maybe after the next key, and would take the highlight back.
    /// Each arrival's echo is taken once, so VoiceOver going back there
    /// later is followed (the diff review's R3, 2026-11-11).
    func followFocus(to id: UUID, now: ContinuousClock.Instant = .now) {
        if let arrived = arrivedAt.removeValue(forKey: id), now - arrived < .seconds(1) {
            return // the echo: on it already, or the keys went on since
        }
        guard highlighted != id else { return }
        followVoiceOver(to: id)
        guard highlighted == id else { return }
        litAt = now
        litByFocus = id
    }

    /// The focus left the control `followFocus` lit, for none of these
    /// controls: the highlight goes out with it, as plain Return then acts
    /// on nothing (a window that drops the focus it opened with:
    /// `HostedWindowController.show`).
    func focusGone() {
        guard let lit = litByFocus, highlighted == lit else { return }
        litByFocus = nil
        highlighted = nil
    }

    /// Without Accessibility, SwiftUI said VoiceOver moved (a step late) and
    /// nothing put the highlight where it is in the last half second: it
    /// may be on a control VoiceOver left for one the focus can't reach (a
    /// dimmed one, or any with keyboard navigation off), so it goes out, and
    /// plain Return and Space act on the focus, as in any Mac window (the
    /// diff review's R4, 2026-11-11).
    func voiceOverMoved(now: ContinuousClock.Instant = .now) {
        guard highlighted != nil, now - (litAt ?? now - .seconds(1)) > .milliseconds(500) else { return }
        litByFocus = nil
        highlighted = nil
    }

    /// The pointer came onto a control (`true`) or left it.
    func hover(_ id: UUID, _ inside: Bool) {
        guard followsPointer else { return }
        hovered.removeAll { $0 == id }
        if inside {
            hovered.append(id)
            point(at: innermostHovered())
            onHighlight?()
        } else if highlighted == id {
            point(at: innermostHovered())
        }
    }

    /// The highlight where the pointer put it (`nil`: none).
    private func point(at id: UUID?) {
        orderOnArrival = nil
        litByFocus = nil
        highlighted = id
        if let id { light(id).byKeys = false }
    }

    private func hidesFocusIfLit() {
        let hides = highlighted != nil || partner?.highlighted != nil
        if hides != hidesFocus { hidesFocus = hides }
    }

    /// Of the controls under the pointer but `excluded`, the last it came
    /// onto, or one inside it, whichever was told first (SwiftUI tells a
    /// control inside another and the one around it in no set order). Not
    /// a dimmed one, which would hold the highlight unseen, the focus's
    /// tint hidden and its keys taken for nothing (app-models-2, the bug
    /// hunt, 2026-11-10), unless it explains itself (the pointer then has
    /// its help tag); nor a list that's one stop (`Control.scroll`, the
    /// logs' entries), whose ring shows only the keys' and which has
    /// nothing to press (R2 of the keyboard fixes' review, 2026-11-10).
    private func innermostHovered(excluding excluded: UUID? = nil) -> UUID? {
        let hovered = hovered.filter { id in
            id != excluded && controls[id].map { ($0.isEnabled || $0.explains) && $0.scroll == nil } != false
        }
        guard var best = hovered.last else { return nil }
        for id in hovered.reversed() where id != best && isInside(id, best) { best = id }
        return best
    }

    /// Whether `inner`'s frame lies within `outer`'s, and is smaller.
    private func isInside(_ inner: UUID, _ outer: UUID) -> Bool {
        guard let a = controls[inner]?.frame, let b = controls[outer]?.frame, a != .zero, a != b else { return false }
        return b.contains(a)
    }

    /// Nothing highlighted, as the menu opens or the keyboard's focus takes over.
    func clear() {
        hovered = []
        litByFocus = nil
        highlighted = nil
        revealed = nil
        wantsFirst = false
        earlyFrames = [:]
        orderOnArrival = nil
    }

    /// `rows`: the order the keys moved by, kept if `id` shows a reason
    /// (`orderOnArrival`); `nil`: the order now.
    func highlight(_ id: UUID, in rows: [[UUID]]? = nil) {
        orderOnArrival = controls[id]?.explains == true ? (id, rows ?? self.rows) : nil
        highlighted = id
        light(id).byKeys = true
        revealed = id
        light(id).arrivals += 1
        arrivedAt[id] = .now
        litAt = .now
        litByFocus = nil
        onHighlight?()
        followWithZoom(id)
    }

    /// Presses the highlighted control; `false` when there's none to press.
    @discardableResult func press() -> Bool {
        guard let control = highlightedControl, let press = control.press else { return false }
        keysActed()
        isPressing = true
        defer { isPressing = false }
        press()
        return true
    }

    /// Space on the highlighted control: its `select`, else `press`.
    @discardableResult func select() -> Bool {
        guard let select = highlightedControl?.select else { return press() }
        keysActed()
        select()
        return true
    }

    /// A key acted on the highlighted control: it's the keys' now, so the
    /// focus a window then drops doesn't take it out (`focusGone`; the
    /// 1.4.0 review's W-1, 2026-11-11: a second plain Space did nothing).
    private func keysActed() {
        litByFocus = nil
        litAt = .now
    }

    /// Whether the keys are pressing the highlighted control now (`press`):
    /// what the press does may move the highlight on (Restore Defaults).
    @ObservationIgnored private(set) var isPressing = false

    /// Delete on the highlighted control; `false` when it takes none.
    @discardableResult func delete() -> Bool {
        guard let delete = highlightedControl?.delete else { return false }
        keysActed()
        delete()
        return true
    }

    /// ← or → on the highlighted control; `false` when it takes neither.
    @discardableResult func adjust(_ step: Int) -> Bool {
        guard let adjust = highlightedControl?.adjust else { return false }
        keysActed()
        adjust(step)
        return true
    }

    /// ↑ or ↓ on the highlighted control, if it scrolls (`Control.scroll`);
    /// `false` when it doesn't, or is at that end.
    func scroll(_ step: Int) -> Bool {
        guard highlightedControl?.scroll?(step) == true else { return false }
        keysActed() // as a press: the window lets the focus go after it (R1)
        return true
    }

    /// The highlighted control opens a side window.
    var highlightedOpensSide: Bool { highlightedControl?.opensSide ?? false }

    /// The highlighted control stands for something shown (`Control.isCurrent`:
    /// Settings' sidebar, a page's row), unlike its foot's link (N7, 2026-11-06).
    var highlightedStandsForShown: Bool { highlightedControl?.isCurrent != nil }

    /// The highlighted control stands for what's shown now, and it is (Settings'
    /// sidebar: the shown page's row, not another Tab stopped on).
    var highlightedIsShown: Bool { highlightedControl?.isCurrent?() == true }

    /// The keys, not the pointer, put the highlight where it is.
    var isLitByKeys: Bool { highlighted.map { light($0).byKeys } ?? false }

    private var highlightedControl: Control? {
        highlighted.flatMap { controls[$0] }.flatMap { $0.isEnabled ? $0 : nil }
    }
}
