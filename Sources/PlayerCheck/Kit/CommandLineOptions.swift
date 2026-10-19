import Foundation
import CheckedPlayers

/// playercheck's command line: read by the helper without the app it names,
/// and written with these by whoever runs it (AutoHush's Add an App…, the
/// Player Check app), so a flag can't be spelled two ways.
package enum CommandLineOptions {
    /// --block-input: while the test moves the window and presses, whoever
    /// runs it can't click, scroll or type (Escape stops the check).
    package static let blockInput = "--block-input"
    /// --read-only: the checks without the test.
    package static let readOnly = "--read-only"
    /// --partial: a test goes on with Accessibility only (Add an App… says
    /// what's missing first).
    package static let partial = "--partial"
    /// --no-taps: AntiDot mode's promise, no audio taps at all.
    package static let noTaps = "--no-taps"
    /// --developer: the report also says, for whoever adds a player to
    /// AutoHush's code, how a built-in player of the app's kind would be made
    /// (AutoHush's own types). The Player Check app passes it; Add an App…
    /// doesn't, so its report ends with what the check found.
    package static let developer = "--developer"
    /// --via <way>: the one way a --play or --pause uses (`CheckResult.WayKind`'s names).
    package static let via = "--via"
    /// --result <file>: where a check writes what it found (`CheckResult`, as JSON).
    package static let result = "--result"
    /// --logs <folder> and --caches <folder>: where its log and what it keeps
    /// between runs go.
    package static let logs = "--logs"
    package static let caches = "--caches"
    /// --now-playing-list [hours | --since <unix time>]: the apps macOS keeps
    /// in Now Playing (`NowPlayingListLine`), all or what changed since then.
    package static let nowPlayingList = "--now-playing-list"
    package static let since = "--since"
    /// --now-playing-reasons <app path>…: why each can be in Now Playing
    /// (`NowPlayingReasonsLine`).
    package static let nowPlayingReasons = "--now-playing-reasons"

    /// What --play and --pause do.
    package enum Action: String, CaseIterable, Sendable {
        case play, pause

        /// "--play", "--pause".
        package var option: String { "--" + rawValue }
    }

    /// The questions about one app, each its first argument, the app next:
    /// whether it needs a launch option and runs with it (`LaunchOptionAnswer`),
    /// quitting it and opening it again with it, and the state its window is
    /// in now (`WindowStateAnswer`).
    package enum AppQuery: String, CaseIterable, Sendable {
        case launchOption = "--launch-option", relaunch = "--relaunch", windowState = "--window-state"

        /// Asked about the app at `path`.
        package func arguments(_ path: String) -> [String] { [rawValue, path] }

        /// What each answers when there's no such app (`CheckExitStatus.failed`).
        package static let noApp = "no app found"
    }

    /// The options followed by a value of their own.
    package static let withValues: Set<String> = [via, result, logs, caches]

    /// The value after `option` in `arguments`, if it's given.
    package static func value(of option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The arguments that are neither an option nor an option's value, in
    /// order, wherever they come: the app, or a query's apps
    /// (`--now-playing-reasons <path>…`) and numbers (`--now-playing-list 24`).
    package static func operands(in arguments: [String]) -> [String] {
        arguments.indices.filter { index in
            !arguments[index].hasPrefix("--") && (index == 0 || !withValues.contains(arguments[index - 1]))
        }.map { arguments[$0] }
    }

    /// The app a check or a press is for.
    package static func app(in arguments: [String]) -> String? { operands(in: arguments).first }

    // MARK: - Written by whoever runs it

    /// Where a run's log and what it keeps go, instead of playercheck's own folders.
    package static func folders(logs: String, caches: String) -> [String] {
        [Self.logs, logs, Self.caches, caches]
    }

    /// A check of the app at `path`: blocking the mouse and keyboard while
    /// it moves the window, going on with Accessibility only when `partial`,
    /// writing its result to `result`, with `folders`; no audio taps unless
    /// `taps`; the developer's lines with `developer`.
    package static func check(_ path: String, blockingInput: Bool = true, partial: Bool = false, result: String? = nil,
                              folders: [String] = [], taps: Bool = true, developer: Bool = false) -> [String] {
        [path] + (blockingInput ? [blockInput] : []) + (partial ? [Self.partial] : []) + (result.map { [Self.result, $0] } ?? [])
            + folders + (taps ? [] : [noTaps]) + (developer ? [Self.developer] : [])
    }

    /// A press of the app at `path`: `action`, by `way` alone (else the first
    /// way that works).
    package static func press(_ path: String, _ action: Action, via way: CheckResult.WayKind?) -> [String] {
        [path, action.option] + (way.map { [via, $0.rawValue] } ?? [])
    }

    /// The Now Playing list as macOS's log has it for the last `hours`
    /// (since the Mac started without them).
    package static func nowPlayingList(hours: Int?) -> [String] {
        [nowPlayingList] + (hours.map { [String($0)] } ?? [])
    }

    /// What changed in the Now Playing list since `date`.
    package static func nowPlayingList(since date: Date) -> [String] {
        [nowPlayingList, since, String(date.timeIntervalSince1970)]
    }

    /// Why each app at `paths` can be in Now Playing.
    package static func nowPlayingReasons(_ paths: [String]) -> [String] {
        [nowPlayingReasons] + paths
    }
}
