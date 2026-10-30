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
/// window. The pointer moves it too, as in a menu: the control under it is
/// the highlighted one. Each control registers itself (`Highlightable`)
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
        /// A dimmed one is skipped.
        var isEnabled = true
        var press: (() -> Void)?
        /// ← (-1) or → (1): a slider's step, a choice's next option.
        var adjust: ((Int) -> Void)?
        /// What Delete does: removes it (an added app's tile), once confirmed.
        var delete: (() -> Void)?
        /// Pressing it opens a side window, which → does too.
        var opensSide = false
        /// It stands for what's shown now (Settings' sidebar: the page's row).
        var isCurrent: (() -> Bool)?
    }

    /// The control the arrow keys or the pointer moved to.
    private(set) var highlighted: UUID? {
        didSet {
            guard highlighted != oldValue else { return }
            if let oldValue { lights[oldValue]?.isOn = false }
            if let highlighted { light(highlighted).isOn = true }
        }
    }
    /// The control the arrow keys moved to last, to scroll into view; the
    /// pointer's never needs it.
    private(set) var revealed: UUID?
    @ObservationIgnored private var controls: [UUID: Control] = [:]
    /// Something is highlighted now, by the keys or the pointer: Settings
    /// takes it from the other side's highlight, one at a time.
    @ObservationIgnored var onHighlight: (() -> Void)?
    @ObservationIgnored private var wantsFirst = false
    /// Frames that came before their control registered.
    @ObservationIgnored private var earlyFrames: [UUID: CGRect] = [:]
    /// The controls the pointer is over now. One can be inside another (the
    /// menu card's Change Player row in the card): the innermost is
    /// highlighted, and leaving it gives the highlight back to the one
    /// around it (the user, 2026-10-26: the card lost its tint once the
    /// pointer had been on the row).
    @ObservationIgnored private var hovered: [UUID] = []
    /// Each control's own "highlighted", so a move redraws the two controls
    /// it concerns, not every one (the full check, 2026-10-18).
    @ObservationIgnored private var lights: [UUID: Light] = [:]

    /// Whether one control is highlighted, observed by that control alone.
    @MainActor @Observable final class Light {
        fileprivate(set) var isOn = false
    }

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
    /// card's Try Again), as leaving it does; none, without one.
    func update(_ id: UUID, isEnabled: Bool) {
        controls[id]?.isEnabled = isEnabled
        if !isEnabled, highlighted == id { highlighted = innermostHovered(excluding: id) }
    }

    func remove(_ id: UUID) {
        controls[id] = nil
        earlyFrames[id] = nil
        hovered.removeAll { $0 == id }
        if highlighted == id { highlighted = innermostHovered() }
        lights[id] = nil
    }

    /// The pointer came onto a control (`true`) or left it.
    func hover(_ id: UUID, _ inside: Bool) {
        hovered.removeAll { $0 == id }
        if inside {
            hovered.append(id)
            highlighted = innermostHovered()
            onHighlight?()
        } else if highlighted == id {
            highlighted = innermostHovered()
        }
    }

    /// Of the controls under the pointer but `excluded`, the last it came
    /// onto, or one inside it, whichever was told first (SwiftUI tells a
    /// control inside another and the one around it in no set order).
    private func innermostHovered(excluding excluded: UUID? = nil) -> UUID? {
        let hovered = hovered.filter { $0 != excluded }
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
        highlighted = nil
        revealed = nil
        wantsFirst = false
        earlyFrames = [:]
    }

    /// The enabled controls in reading order, by row: part by part
    /// (`Control.band`), in each row by row from the top (a control within
    /// 6 pt of a row's top is on it), each row left to right.
    var rows: [[UUID]] {
        let enabled = controls.filter(\.value.isEnabled).sorted { a, b in
            let (a, b) = (a.value, b.value)
            if a.band != b.band { return a.band < b.band }
            return a.frame.minY != b.frame.minY ? a.frame.minY < b.frame.minY : a.frame.minX < b.frame.minX
        }
        var rows: [[(id: UUID, control: Control)]] = []
        for (id, control) in enabled {
            if let first = rows.last?.first?.control, first.band == control.band, control.frame.minY - first.frame.minY <= 6 {
                rows[rows.count - 1].append((id, control))
            } else {
                rows.append([(id, control)])
            }
        }
        return rows.map { $0.sorted { $0.control.frame.minX < $1.control.frame.minX }.map(\.id) }
    }

    /// The highlight `step` rows on (1 down, -1 up), wrapping at the ends:
    /// in a row of several (durations, tiles), the one nearest above or
    /// under, else the row's first (the user, 2026-10-18: ← and → move
    /// within a row); from nothing, the first row (down) or the last (up).
    func move(_ step: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let next: UUID
        if let highlighted, let row = rows.firstIndex(where: { $0.contains(highlighted) }) {
            let target = rows[((row + step) % rows.count + rows.count) % rows.count]
            if rows[row].count > 1, let from = controls[highlighted]?.frame.midX {
                next = target.min { abs((controls[$0]?.frame.midX ?? 0) - from) < abs((controls[$1]?.frame.midX ?? 0) - from) } ?? target[0]
            } else {
                next = target[0]
            }
        } else {
            next = (step > 0 ? rows[0] : rows[rows.count - 1])[0]
        }
        highlight(next)
    }

    /// The highlight `step` controls along its row (← -1, → 1); `false` at
    /// the row's end, or in a row of one.
    @discardableResult func moveInRow(_ step: Int) -> Bool {
        guard let highlighted, let row = rows.first(where: { $0.contains(highlighted) }),
              let index = row.firstIndex(of: highlighted), row.indices.contains(index + step) else { return false }
        highlight(row[index + step])
        return true
    }

    /// The highlight on the first control as soon as they've come (a side
    /// window just opened by →, as a submenu's first item lights up).
    func highlightFirstWhenReady() {
        wantsFirst = true
        firstWhenReady()
    }

    private func highlight(_ id: UUID) {
        highlighted = id
        revealed = id
        onHighlight?()
    }

    /// Once the controls that came in the same update have registered (the
    /// next turn of the run loop) and been placed: a frame that comes later
    /// tries again (`update(_:frame:)`), so it never lights one at random.
    private func firstWhenReady() {
        guard wantsFirst, !controls.isEmpty else { return }
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.wantsFirst, !self.controls.isEmpty,
                      !self.controls.values.contains(where: { $0.frame == .zero }) else { return }
                self.wantsFirst = false
                if self.highlighted == nil { self.move(1) }
            }
        }
    }

    /// The highlight on the control that stands for what's shown now
    /// (`Control.isCurrent`), if one does.
    func highlightCurrent() {
        // The first in reading order, when several do (a card's rows).
        guard let current = rows.joined().first(where: { controls[$0]?.isCurrent?() == true }) else { return }
        highlight(current)
    }

    /// Presses the highlighted control; `false` when there's none to press.
    @discardableResult func press() -> Bool {
        guard let control = highlightedControl, let press = control.press else { return false }
        isPressing = true
        defer { isPressing = false }
        press()
        return true
    }

    /// Whether the keys are pressing the highlighted control now (`press`):
    /// what the press does may move the highlight on (Restore Defaults).
    @ObservationIgnored private(set) var isPressing = false

    /// The highlight on the first control of `group` that takes it (a
    /// card's first usable row), once what the press changed is drawn: a
    /// row it turns on or off has registered so by then.
    func highlightFirst(in group: UUID) {
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let first = self.rows.joined().first(where: { self.controls[$0]?.group == group }) else { return }
                self.highlight(first)
            }
        }
    }

    /// Delete on the highlighted control; `false` when it takes none.
    @discardableResult func delete() -> Bool {
        guard let delete = highlightedControl?.delete else { return false }
        delete()
        return true
    }

    /// ← or → on the highlighted control; `false` when it takes neither.
    @discardableResult func adjust(_ step: Int) -> Bool {
        guard let adjust = highlightedControl?.adjust else { return false }
        adjust(step)
        return true
    }

    /// The highlighted control opens a side window.
    var highlightedOpensSide: Bool { highlightedControl?.opensSide ?? false }

    private var highlightedControl: Control? {
        highlighted.flatMap { controls[$0] }.flatMap { $0.isEnabled ? $0 : nil }
    }
}

/// The part of a window a highlightable control is in, top to bottom: the
/// keys go through one before the next. In the menu, the card is pinned
/// over what scrolls and the buttons under it; in Settings → Sound Sources,
/// the heading over the apps' list and the buttons under it.
enum HighlightBand: Int, Comparable {
    case top, middle, bottom

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
