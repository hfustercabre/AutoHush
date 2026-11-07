import CoreGraphics
import Foundation

// KeyHighlight: the order the keys go by, and their moves through it.
extension KeyHighlight {
    /// The enabled controls (and the dimmed ones that explain themselves)
    /// in reading order, by row: part by part
    /// (`Control.band`), in each row by row from the top (a control within
    /// 6 pt of a row's top is on it), each row left to right.
    var rows: [[UUID]] {
        let enabled = controls.filter { $0.value.isEnabled || $0.value.explains }.sorted { a, b in
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
        let rows = keyRows
        guard !rows.isEmpty else { return }
        let next: UUID
        if let highlighted, let row = rows.firstIndex(where: { $0.contains(highlighted) }) {
            next = entry(to: rows[((row + step) % rows.count + rows.count) % rows.count], from: rows[row], highlighted)
        } else {
            next = (step > 0 ? rows[0] : rows[rows.count - 1])[0]
        }
        highlight(next, in: rows)
    }

    /// The order the keys move by: `rows`, or, from a control that shows
    /// a reason, the order as they came onto it (`orderOnArrival`).
    private var keyRows: [[UUID]] {
        if let orderOnArrival, orderOnArrival.id == highlighted { return orderOnArrival.rows }
        return rows
    }

    /// The highlight on the first row whose top is at `y` or under it, in
    /// reading order (or the first row, with none): out of a field that
    /// takes no highlight itself (Settings → Sound Sources' search), into
    /// the rows under it, not the ones beside it (N4, 2026-11-06).
    func highlightFirst(below y: CGFloat) {
        let rows = rows
        guard let row = rows.first(where: { (controls[$0[0]]?.frame.minY ?? 0) >= y }) ?? rows.first else { return }
        highlight(row[0], in: rows)
    }

    /// Where the highlight lands in `target` from `highlighted` in `row`:
    /// from a row of several, the nearest above or under; else the first.
    private func entry(to target: [UUID], from row: [UUID], _ highlighted: UUID) -> UUID {
        guard row.count > 1, let from = controls[highlighted]?.frame.midX else { return target[0] }
        return target.min { abs((controls[$0]?.frame.midX ?? 0) - from) < abs((controls[$1]?.frame.midX ?? 0) - from) } ?? target[0]
    }

    /// Page Down (Up): the highlight about a page on (back) in its part
    /// (`Control.band`), to the last row that ends within `pageHeight` of
    /// where its own starts, at least one row; from its part's last row (first), into
    /// the next part (previous); at the end, it stays: no wrapping, as in
    /// macOS's lists. Home and End: the first row and the last. From
    /// nothing, Page Down and Home light the first row, Page Up and End the
    /// last (A12, 2026-11-01: Apple's standard keys, fn with the arrows on a laptop).
    func jump(_ jump: Jump) {
        let rows = keyRows
        guard !rows.isEmpty else { return }
        let step = jump == .pageDown || jump == .first ? 1 : -1
        guard jump == .pageUp || jump == .pageDown,
              let highlighted, let row = rows.firstIndex(where: { $0.contains(highlighted) }) else {
            return highlight((step > 0 ? rows[0] : rows[rows.count - 1])[0], in: rows)
        }
        let target = pageTarget(from: row, step: step, in: rows)
        guard target != row else { return }
        highlight(entry(to: rows[target], from: rows[row], highlighted), in: rows)
    }

    /// The row a page on from `row` (`jump`).
    private func pageTarget(from row: Int, step: Int, in rows: [[UUID]]) -> Int {
        guard let start = controls[rows[row][0]] else { return row }
        let page = pageHeight ?? .infinity
        var target = row
        var next = row + step
        while rows.indices.contains(next), let control = controls[rows[next][0]], control.band == start.band {
            let distance = step > 0 ? control.frame.maxY - start.frame.minY : start.frame.maxY - control.frame.minY
            if distance > page, target != row { break }
            target = next
            if distance > page { break }
            next += step
        }
        // Its part's end: the next part's first row (or the previous one's last).
        if target == row, rows.indices.contains(row + step) { target = row + step }
        return target
    }

    /// The highlight `step` controls along its row (← -1, → 1); `false` at
    /// the row's end, or in a row of one.
    @discardableResult func moveInRow(_ step: Int) -> Bool {
        let rows = keyRows
        guard let highlighted, let row = rows.first(where: { $0.contains(highlighted) }),
              let index = row.firstIndex(of: highlighted), row.indices.contains(index + step) else { return false }
        highlight(row[index + step], in: rows)
        return true
    }

    /// The highlight on the control that stands for what's shown now
    /// (`Control.isCurrent`), if one does.
    func highlightCurrent() {
        // The first in reading order, when several do (a card's rows).
        guard let current = rows.joined().first(where: { controls[$0]?.isCurrent?() == true }) else { return }
        highlight(current)
    }

    /// The highlight arrives again where it is, by the keys: VoiceOver's
    /// cursor and Zoom go back to it (the menu's row, as the side window it
    /// opened closes: VO1, the a11y audit, 2026-11-06).
    func arriveAgain() {
        guard let highlighted else { return }
        highlight(highlighted)
    }
}
