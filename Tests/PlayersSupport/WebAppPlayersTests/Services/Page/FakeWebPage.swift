import Foundation
import os
@testable import WebAppPlayers
import AutoHushTestSupport

/// A web app's page in memory: buttons by number, each with its words and
/// place; a press runs `onPress`.
final class FakeWebPage: WebPage, @unchecked Sendable {
    struct Button {
        var label: String
        var isEnabled = true
        var place: ButtonPlace
        /// Scrolled out of sight; among a player's controls (a slider).
        var outOfSight = false
        var withControls = false
    }

    private let lock = NSLock()
    private var _buttons: [Int: Button] = [:]
    private var _hasWindow = true
    private var _sound = false
    private var _trusted = true
    private var _presses: [Int] = []
    private var _looks = 0
    private var _windowLooks = 0
    private var _buttonReads = 0
    private var _blankLooks = 0
    private var _wordsCurrent = true
    private var _pressFails = false
    private var _releases = 0
    /// What a press does; by default it swaps the button's words.
    var onPress: (@Sendable (FakeWebPage, Int) -> Void)?

    var buttonsByNumber: [Int: Button] {
        get { lock.withLock { _buttons } }
        set { lock.withLock { _buttons = newValue } }
    }
    var hasWindow: Bool {
        get { lock.withLock { _hasWindow } }
        set { lock.withLock { _hasWindow = newValue } }
    }
    var sound: Bool {
        get { lock.withLock { _sound } }
        set { lock.withLock { _sound = newValue } }
    }
    var trusted: Bool {
        get { lock.withLock { _trusted } }
        set { lock.withLock { _trusted = newValue } }
    }
    /// The next looks that find no buttons, as WebKit answers the first
    /// question about a page it hasn't built for Accessibility yet.
    var blankLooks: Int {
        get { lock.withLock { _blankLooks } }
        set { lock.withLock { _blankLooks = newValue } }
    }
    /// Whether its words are current (false: a Chromium page out of sight).
    var wordsCurrent: Bool {
        get { lock.withLock { _wordsCurrent } }
        set { lock.withLock { _wordsCurrent = newValue } }
    }
    /// A press can't be made (Accessibility refuses it): nothing is pressed.
    var pressFails: Bool {
        get { lock.withLock { _pressFails } }
        set { lock.withLock { _pressFails = newValue } }
    }
    /// How many times its switch was released.
    var releases: Int { lock.withLock { _releases } }
    var presses: [Int] { lock.withLock { _presses } }
    /// How many times every button was looked for.
    var looks: Int { lock.withLock { _looks } }
    /// How many times it was asked whether it has a window.
    var windowLooks: Int { lock.withLock { _windowLooks } }
    /// How many times a button known already was read.
    var buttonReads: Int { lock.withLock { _buttonReads } }

    func set(_ number: Int, label: String) {
        lock.withLock { _buttons[number]?.label = label }
    }

    /// Every element is new, as after a reload: the numbers move up by `offset`.
    func reload(offset: Int) {
        lock.withLock { _buttons = Dictionary(uniqueKeysWithValues: _buttons.map { ($0.key + offset, $0.value) }) }
    }

    // MARK: - WebPage

    func isTrusted(prompt: Bool) -> Bool { trusted }

    func hasWindow(pid: pid_t) -> Bool {
        lock.withLock {
            _windowLooks += 1
            return _hasWindow
        }
    }

    func buttons(pid: pid_t) -> [PageButton]? {
        lock.withLock {
            _looks += 1
            guard _hasWindow else { return nil }
            if _blankLooks > 0 {
                _blankLooks -= 1
                return []
            }
            return _buttons.keys.sorted().map {
                PageButton(handle: ButtonHandle($0), label: _buttons[$0]!.label, isEnabled: _buttons[$0]!.isEnabled)
            }
        }
    }

    func button(_ handle: ButtonHandle) -> PageButton? {
        lock.withLock {
            _buttonReads += 1
            guard let number = handle.element.base as? Int, let button = _buttons[number] else { return nil }
            return PageButton(handle: handle, label: button.label, isEnabled: button.isEnabled)
        }
    }

    func place(of handle: ButtonHandle) -> ButtonPlace? {
        lock.withLock { (handle.element.base as? Int).flatMap { _buttons[$0]?.place } }
    }

    func standing(of handle: ButtonHandle) -> ButtonStanding? {
        lock.withLock {
            (handle.element.base as? Int).flatMap { _buttons[$0] }
                .map { ButtonStanding(isInWindow: !$0.outOfSight, isWithPlayerControls: $0.withControls) }
        }
    }

    func press(_ handle: ButtonHandle) -> Bool {
        guard !pressFails, let number = handle.element.base as? Int, buttonsByNumber[number] != nil else { return false }
        lock.withLock { _presses.append(number) }
        if let onPress { onPress(self, number) } else { swapWords(of: number) }
        return true
    }

    func isPlayingSound(pid: pid_t) -> Bool { sound }

    func wordsAreCurrent(pid: pid_t) -> Bool { wordsCurrent }

    func release() { lock.withLock { _releases += 1 } }

    /// "Play" ↔ "Pause", in any language and on any player bar (SoundCloud's) the tests use.
    func swapWords(of number: Int) {
        let swaps = ["Play": "Pause", "Pause": "Play", "Reproducir": "Pausar", "Pausar": "Reproducir",
                     "Play current": "Pause current", "Pause current": "Play current"]
        lock.withLock {
            if let label = _buttons[number]?.label, let other = swaps[label] { _buttons[number]?.label = other }
        }
    }
}
