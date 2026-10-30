import AutoHushKit
import CheckedPlayers
import Foundation
import PlayerCheckKit

/// Playing and pausing an app by a way its check found, and relaunching it.
extension Checker {
    /// Whether its Play and Pause buttons show: some way worked in its last
    /// finished check, in every window state or some. Which one a press uses
    /// depends on the state its window is in then (`controlByState`).
    func hasWorkingWay(_ app: InstalledApp) -> Bool {
        finished[app.id]?.ways.contains { $0.canControl && ($0.mark == .works || $0.mark == .some) } ?? false
    }

    /// Plays or pauses it by the first way that worked in its last check with
    /// its window as it is now: playercheck --window-state tells the state,
    /// then --via that way alone.
    func controlByState(_ app: InstalledApp, _ action: CommandLineOptions.Action) {
        guard !isBusy, let tool, let ways = finished[app.id]?.ways else { return }
        controllingID = app.id
        controls[app.id] = ((action == .play ? "Playing" : "Pausing") + "…", nil)
        Task {
            let (_, output) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.windowState.arguments(app.url.path))
            controllingID = nil
            // Without a window (or not known), only a way that worked in every state.
            let known = WindowStateAnswer(line: output)?.windowState
            guard let way = ways.first(where: { $0.canControl && (known.map($0.passes) ?? ($0.mark == .works)) }), let via = way.via else {
                controls[app.id] = (known.map { "No way worked in its check with its window \($0.title)." }
                                    ?? "No way worked in every window state in its check.", false)
                return
            }
            control(app, action, via: via, note: known.map { "Its window \($0.title): by \(via.inSentence)." })
        }
    }

    /// Plays or pauses it by that one way: playercheck --play or --pause
    /// --via `via` tries no other. `stopPress` ends it. `note` goes before
    /// what playercheck says (the window's state and the way chosen).
    func control(_ app: InstalledApp, _ action: CommandLineOptions.Action, via: CheckResult.WayKind, note: String? = nil) {
        guard !isBusy, let tool else { return }
        let run: LineRun
        do {
            run = try LineRun(tool, CommandLineOptions.press(app.url.path, action, via: via))
        } catch {
            controls[app.id] = ("Couldn't run playercheck: \(error.localizedDescription)", false)
            return
        }
        controllingID = app.id
        controls[app.id] = ((action == .play ? "Playing" : "Pausing") + "…", nil)
        pressProcess = run.running
        pressStopped = false
        Task {
            var output: [String] = []
            for await line in run.lines { output.append(line) }
            let status = await run.status()
            let said = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            controls[app.id] = pressStopped
                ? ("Stopped before it said whether it worked.", false)
                : ((note.map { $0 + " " } ?? "") + said, status == CheckExitStatus.done)
            pressProcess = nil
            controllingID = nil
            readClients()
        }
    }

    /// For an Electron app: the launch option it needs, and whether it runs
    /// with it (`launchOptions`), asked of playercheck.
    func readLaunchOption(_ app: InstalledApp) {
        guard let tool, app.isElectron else { return }
        Task {
            let (status, output) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.launchOption.arguments(app.url.path))
            guard status == CheckExitStatus.done, let answer = LaunchOptionAnswer(line: output), let option = answer.option else {
                launchOptions[app.id] = nil
                return
            }
            launchOptions[app.id] = (option, answer.running)
        }
    }

    /// Quits the app and opens it again with its launch option, in the
    /// background (playercheck --relaunch), then reads the option again.
    func relaunch(_ app: InstalledApp) {
        guard !isBusy, relaunchingID == nil, let tool else { return }
        relaunchingID = app.id
        relaunches[app.id] = nil
        Task {
            let (status, output) = await Self.runAndWait(tool, CommandLineOptions.AppQuery.relaunch.arguments(app.url.path))
            relaunches[app.id] = (output.trimmingCharacters(in: .whitespacesAndNewlines), status == CheckExitStatus.done)
            relaunchingID = nil
            refreshRunning()
            readLaunchOption(app)
        }
    }

    /// Stops a Play or Pause (it may be waiting on an app, or on macOS's
    /// Automation prompt): playercheck turns back off the switches it turned on.
    func stopPress() {
        guard let pressProcess else { return }
        pressStopped = true
        pressProcess.stop()
    }

    /// When the app quits: stops what runs, so no playercheck goes on unwatched.
    func stopAll() {
        stop()
        stopPress()
    }
}
