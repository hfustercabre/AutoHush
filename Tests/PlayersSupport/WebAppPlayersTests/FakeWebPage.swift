import Foundation
import os
import AutoHushKit
@testable import WebAppPlayers

/// A web app's page in memory: buttons by number, each with its words and
/// place; a press runs `onPress`.
final class FakeWebPage: WebPage, @unchecked Sendable {
    struct Button {
        var label: String
        var isEnabled = true
        var place: ButtonPlace
    }

    private let lock = NSLock()
    private var _buttons: [Int: Button] = [:]
    private var _hasWindow = true
    private var _sound = false
    private var _trusted = true
    private var _presses: [Int] = []
    private var _looks = 0
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
    var presses: [Int] { lock.withLock { _presses } }
    /// How many times every button was looked for.
    var looks: Int { lock.withLock { _looks } }

    func set(_ number: Int, label: String) {
        lock.withLock { _buttons[number]?.label = label }
    }

    /// Every element is new, as after a reload: the numbers move up by `offset`.
    func reload(offset: Int) {
        lock.withLock { _buttons = Dictionary(uniqueKeysWithValues: _buttons.map { ($0.key + offset, $0.value) }) }
    }

    // MARK: - WebPage

    func isTrusted(prompt: Bool) -> Bool { trusted }

    func buttons(pid: pid_t) -> [PageButton]? {
        lock.withLock {
            _looks += 1
            guard _hasWindow else { return nil }
            return _buttons.keys.sorted().map {
                PageButton(handle: ButtonHandle($0), label: _buttons[$0]!.label, isEnabled: _buttons[$0]!.isEnabled)
            }
        }
    }

    func button(_ handle: ButtonHandle) -> PageButton? {
        lock.withLock {
            guard let number = handle.element.base as? Int, let button = _buttons[number] else { return nil }
            return PageButton(handle: handle, label: button.label, isEnabled: button.isEnabled)
        }
    }

    func place(of handle: ButtonHandle) -> ButtonPlace? {
        lock.withLock { (handle.element.base as? Int).flatMap { _buttons[$0]?.place } }
    }

    func press(_ handle: ButtonHandle) -> Bool {
        guard let number = handle.element.base as? Int, buttonsByNumber[number] != nil else { return false }
        lock.withLock { _presses.append(number) }
        if let onPress { onPress(self, number) } else { swapWords(of: number) }
        return true
    }

    func isPlayingSound(pid: pid_t) -> Bool { sound }

    /// "Play" ↔ "Pause", in any language the tests use.
    func swapWords(of number: Int) {
        let swaps = ["Play": "Pause", "Pause": "Play", "Reproducir": "Pausar", "Pausar": "Reproducir"]
        lock.withLock {
            if let label = _buttons[number]?.label, let other = swaps[label] { _buttons[number]?.label = other }
        }
    }
}

/// Places used by the tests: a player bar at the bottom, the page's main part higher up.
enum Places {
    static let playerBar = ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkComplementary"], distanceFromBottom: 40)
    static let main = ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain"], distanceFromBottom: 600)
    static let fullScreen = ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain", "AXGroup"], distanceFromBottom: 300)
}

/// Recipes kept in memory.
final class MemoryRecipeStore: PlayPauseRecipeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var recipes: [String: PlayPauseRecipe] = [:]

    init(_ recipes: [String: PlayPauseRecipe] = [:]) {
        self.recipes = recipes
    }

    func recipe(for bundleID: String) -> PlayPauseRecipe? { lock.withLock { recipes[bundleID] } }
    func save(_ recipe: PlayPauseRecipe, for bundleID: String) { lock.withLock { recipes[bundleID] = recipe } }
}

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
}

/// Records mutes; `canMute` false stands for a missing permission.
final class FakeMuter: AudioMuting, @unchecked Sendable {
    private let lock = NSLock()
    private var _muted: Set<pid_t> = []
    private var _log: [String] = []
    var canMute = true

    var muted: Set<pid_t> { lock.withLock { _muted } }
    var log: [String] { lock.withLock { _log } }

    func mute(appPID: pid_t) -> Bool {
        lock.withLock {
            guard canMute else { return false }
            _muted.insert(appPID)
            _log.append("mute \(appPID)")
            return true
        }
    }

    func unmute(appPID: pid_t) {
        lock.withLock {
            if _muted.remove(appPID) != nil { _log.append("unmute \(appPID)") }
        }
    }
}

/// Says whether the web app can be heard; counts how often it listened.
final class FakeLevelProbe: AudioLevelProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _audible = false
    private var _listens = 0

    var audible: Bool {
        get { lock.withLock { _audible } }
        set { lock.withLock { _audible = newValue } }
    }
    var listens: Int { lock.withLock { _listens } }

    func isAudible(appPID: pid_t) -> Bool {
        lock.withLock {
            _listens += 1
            return _audible
        }
    }
}
