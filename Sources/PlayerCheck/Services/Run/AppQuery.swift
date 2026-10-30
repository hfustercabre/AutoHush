import AppKit
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit

/// --launch-option, --relaunch and --window-state <app>, for AutoHush's Add
/// an App… (the first two) and the Player Check app: whether the app needs a
/// launch option and runs with it (`LaunchOptionAnswer`), quitting it and
/// opening it again with that option (logged in --logs' folder, when given),
/// and the state its window is in now (`WindowStateAnswer`), for its Play
/// and Pause by the way that worked in that state.
typealias AppQuery = CommandLineOptions.AppQuery

@MainActor func answer(_ query: AppQuery) -> Never {
    guard arguments.count > 1, let url = findApp(arguments[1]), let id = Bundle(url: url)?.bundleIdentifier else {
        print(AppQuery.noApp)
        exit(CheckExitStatus.failed)
    }
    let app = NSRunningApplication.running(id)
    switch query {
    case .launchOption:
        let needed = LaunchOption.needed(by: url)
        let running: LaunchOptionAnswer.Running? = needed.map { needed in
            guard let app else { return .notRunning }
            return ProcessArguments.of(app.processIdentifier).contains(needed) ? .yes : .no
        }
        print(LaunchOptionAnswer(option: needed, running: running).line)
        exit(CheckExitStatus.done)
    case .relaunch:
        // It quits and opens the app, so it's logged as checks and presses
        // are (in --logs' folder); the two questions aren't (they're asked often).
        runLog.start(app: AppName.of(appAt: url), doing: RunLogName.relaunch)
        let tell = { (line: String) in
            log(line)
            print(line)
        }
        guard let needed = LaunchOption.needed(by: url) else {
            tell("It needs no launch option.")
            exit(CheckExitStatus.failed)
        }
        exit(LaunchOption.relaunch(app, url: url, with: needed, tell: tell) ? CheckExitStatus.done : CheckExitStatus.failed)
    case .windowState:
        let answer: WindowStateAnswer = app.map { AppWindows.state(of: $0).map { .state($0) } ?? .noWindow } ?? .notRunning
        print(answer.line)
        exit(CheckExitStatus.done)
    }
}
