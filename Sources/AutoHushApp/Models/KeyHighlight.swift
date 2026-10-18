import CoreGraphics
import Foundation
import Observation

/// The highlight the arrow keys and the pointer move, as macOS's own menus
/// have one whatever the keyboard navigation setting (the user, 2026-10-18:
/// "Arrows, as menus"; Settings too: "Lets add the same over and arrows
/// navigation system to the Settings Window"): ↑ and ↓ move it through the
/// controls in reading order, wrapping at the ends; Return or Space presses
/// the one it's on; ← and → change a slider or a choice, and → opens a side
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
        /// A dimmed one is skipped.
        var isEnabled = true
        var press: (() -> Void)?
        /// ← (-1) or → (1): a slider's step, a choice's next option.
        var adjust: ((Int) -> Void)?
        /// Pressing it opens a side window, which → does too.
        var opensSide = false
        /// It stands for what's shown now (Settings' sidebar: the page's row).
        var isCurrent: (() -> Bool)?
    }

    /// The control the arrow keys or the pointer moved to.
    private(set) var highlighted: UUID?
    /// The control the arrow keys moved to last, to scroll into view; the
    /// pointer's never needs it.
    private(set) var revealed: UUID?
    @ObservationIgnored private var controls: [UUID: Control] = [:]
    /// Something is highlighted now, by the keys or the pointer: Settings
    /// takes it from the other side's highlight, one at a time.
    @ObservationIgnored var onHighlight: (() -> Void)?

    func register(_ id: UUID, _ control: Control) {
        var control = control
        // Its frame may have come first.
        if let frame = controls[id]?.frame, control.frame == .zero { control.frame = frame }
        controls[id] = control
    }

    func update(_ id: UUID, frame: CGRect) {
        controls[id, default: Control()].frame = frame
    }

    func update(_ id: UUID, isEnabled: Bool) {
        controls[id]?.isEnabled = isEnabled
        if !isEnabled, highlighted == id { highlighted = nil }
    }

    func remove(_ id: UUID) {
        controls[id] = nil
        if highlighted == id { highlighted = nil }
    }

    /// The pointer came onto a control (`true`) or left it.
    func hover(_ id: UUID, _ inside: Bool) {
        if inside {
            highlighted = id
            onHighlight?()
        } else if highlighted == id {
            highlighted = nil
        }
    }

    /// Nothing highlighted, as the menu opens or the keyboard's focus takes over.
    func clear() {
        highlighted = nil
        revealed = nil
    }

    /// The enabled controls in reading order: row by row from the top (a
    /// control within 6 pt of a row's top is on it), each row left to right.
    var order: [UUID] {
        let enabled = controls.filter(\.value.isEnabled).sorted {
            $0.value.frame.minY != $1.value.frame.minY ? $0.value.frame.minY < $1.value.frame.minY : $0.value.frame.minX < $1.value.frame.minX
        }
        var rows: [[(id: UUID, frame: CGRect)]] = []
        for (id, control) in enabled {
            if let top = rows.last?.first?.frame.minY, control.frame.minY - top <= 6 {
                rows[rows.count - 1].append((id, control.frame))
            } else {
                rows.append([(id, control.frame)])
            }
        }
        return rows.flatMap { $0.sorted { $0.frame.minX < $1.frame.minX }.map(\.id) }
    }

    /// The highlight `step` controls on (1 down, -1 up), wrapping at the
    /// ends; from nothing, the first (down) or the last (up).
    func move(_ step: Int) {
        let order = order
        guard !order.isEmpty else { return }
        let next: UUID
        if let highlighted, let index = order.firstIndex(of: highlighted) {
            next = order[((index + step) % order.count + order.count) % order.count]
        } else {
            next = step > 0 ? order[0] : order[order.count - 1]
        }
        highlighted = next
        revealed = next
        onHighlight?()
    }

    /// The highlight on the control that stands for what's shown now
    /// (`Control.isCurrent`), if one does.
    func highlightCurrent() {
        guard let current = controls.first(where: { $0.value.isEnabled && $0.value.isCurrent?() == true })?.key else { return }
        highlighted = current
        revealed = current
        onHighlight?()
    }

    /// Presses the highlighted control; `false` when there's none to press.
    @discardableResult func press() -> Bool {
        guard let control = highlightedControl, let press = control.press else { return false }
        press()
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
