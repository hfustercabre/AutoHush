import Foundation
@testable import MenuPlayers

/// Stands in for an app's playback menu: its Play/Pause item toggles when pressed.
final class FakeMenu: PlaybackMenu, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private var _title: String
    private var _enabled: Bool
    private var _trusted: Bool
    private var _found = true
    private var _pressFails = false
    private var _presses = 0
    private var _prompts: [Bool] = []

    init(title: String = "Pause", enabled: Bool = true, trusted: Bool = true) {
        _title = title
        _enabled = enabled
        _trusted = trusted
    }

    var presses: Int { lock.withLock { _presses } }
    var prompts: [Bool] { lock.withLock { _prompts } }

    var title: String {
        get { lock.withLock { _title } }
        set { lock.withLock { _title = newValue } }
    }
    var found: Bool {
        get { lock.withLock { _found } }
        set { lock.withLock { _found = newValue } }
    }
    /// Its item can't be pressed (Accessibility refuses): nothing changes.
    var pressFails: Bool {
        get { lock.withLock { _pressFails } }
        set { lock.withLock { _pressFails = newValue } }
    }

    func isTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            _prompts.append(prompt)
            return _trusted
        }
    }

    func toggle(pid: pid_t) -> MenuToggle? {
        lock.withLock { _found ? MenuToggle(title: _title, isEnabled: _enabled) : nil }
    }

    func pressToggle(pid: pid_t) -> Bool {
        lock.withLock {
            guard !_pressFails else { return false }
            _presses += 1
            _title = _title == "Pause" ? "Play" : "Pause"
            return true
        }
    }
}
