import Foundation
@testable import CheckedPlayers

/// The panel in memory: its rows, the one pressed.
final class FakePanel: NowPlayingPanel, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private var shown: [PanelRow]
    private var pressedRows: [String] = []
    private var opened = 0
    private var _opens = true
    private var _inMenuBar = true
    private var _pressFails = false

    init(_ rows: [PanelRow]) { shown = rows }

    var opens: Bool {
        get { lock.withLock { _opens } }
        set { lock.withLock { _opens = newValue } }
    }
    var inMenuBar: Bool {
        get { lock.withLock { _inMenuBar } }
        set { lock.withLock { _inMenuBar = newValue } }
    }
    /// Its rows' Play/Pause can't be pressed (Accessibility refuses).
    var pressFails: Bool {
        get { lock.withLock { _pressFails } }
        set { lock.withLock { _pressFails = newValue } }
    }

    var pressed: [String] { lock.withLock { pressedRows } }
    /// How many times it was opened.
    var openings: Int { lock.withLock { opened } }

    func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool? {
        guard opens else { return nil }
        let rows = lock.withLock {
            opened += 1
            return shown
        }
        guard let row = pick(rows), !pressFails else { return false }
        lock.withLock { pressedRows.append(row.text) }
        return true
    }

    func isInMenuBar() -> Bool { inMenuBar }
}
