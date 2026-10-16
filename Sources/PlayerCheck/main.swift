// playercheck: could AutoHush control this app as a player, and how? It
// reads the app's scripting dictionary, its playback menu, where its sound
// comes from, whether it holds Now Playing and the buttons of its page (a
// web page in its windows, a Safari web app's or any app's; an Electron or
// CEF app's, or a Flutter app's interface, once a switch for assistive tools
// is on), then lists the ways it could be controlled and says which kind of
// player it could be: scriptable, a menu player, or one that learns its
// page's button. AutoHush's Add an App… runs it (it's inside AutoHush.app),
// and Tools/PlayerCheckApp from a window.
//   playercheck <app name, bundle ID or path>          checks it, and tests each way to control it: pauses
//                                                      and plays it once by each (asking for it to be
//                                                      started first when it isn't playing), with its window
//                                                      in each state a player's can be in (visible, covered,
//                                                      on another desktop, covered there, full screen,
//                                                      minimized, hidden), then puts its window back
//   playercheck <app> --block-input                    the same, blocking clicks, scrolling and keys while it moves
//                                                      the window and presses (Escape stops the check)
//   playercheck <app> --read-only                      checks it without pressing anything
//   playercheck <app> … --result <file>                also writes what it found as JSON (CheckResult), for AutoHush's
//                                                      Add an App…
//   playercheck <app> … --partial [--no-taps]          goes on without Audio Recording or Automation (Accessibility is
//                                                      enough); --no-taps (AntiDot mode) taps no sound at all
//   playercheck <app> … --developer                    the report also says how a built-in player of its kind would be
//                                                      made, with AutoHush's own types (the Player Check app passes it;
//                                                      Add an App… doesn't, so its report ends with what was found)
//   playercheck <app> --play|--pause [--via script|menu|page|panel]
//                                                      just plays or pauses it, by that way (reading only what it
//                                                      needs) or the first that works
//   playercheck --now-playing-list [hours]             the apps macOS keeps in Now Playing, from its log
//                                                      (administrators only): "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>",
//                                                      then "#active\t<pid>"
//   playercheck --now-playing-list --since <unix time> what changed since then, apps gone as "Removed"
//   playercheck --now-playing-reasons <app path>…      why each app can be in Now Playing, as Player Check lists them:
//                                                      "<path>\t<reason>\t<framework>\t<switches>" (each empty when none)
//   playercheck --launch-option <app>                  the launch option it needs (Electron's apps), and whether it
//                                                      runs with it: "<option or nothing>\t<yes|no|not running>"
//   playercheck --relaunch <app>                       quits it, then opens it again with that option, in the background
//   playercheck --window-state <app>                   the state its main window is in now (visible, covered, …)
//   any of them … [--logs <folder>] [--caches <folder>]
//                                                      where its log and what it keeps between runs go (AutoHush passes
//                                                      its own folders), instead of ~/Library/Logs/PlayerCheck and
//                                                      ~/Library/Caches/PlayerCheck
// Each check, press or relaunch is also logged (the last 50), never with the home folder's path or what was playing.
// A target of AutoHush's package, using AutoHush's own code wherever the two
// do the same thing (Apple events, menus, learned page buttons, sound).
// Build: swift build -c release --product playercheck
import AppKit
import AutoHushKit
import CheckedPlayers

// Whoever reads the output may go first (Player Check quitting mid-check):
// writing then fails quietly, and a test that paused the app still plays
// it again and puts back what it changed, instead of being killed.
signal(SIGPIPE, SIG_IGN)
atexit {
    nowPlayingReports.stop()
    log("(ended)")
}

MainActor.assumeIsolated {
    // A one-line answer first: it neither checks nor presses.
    switch CommandLine.arguments.dropFirst().first {
    case NowPlayingApp.argument?:
        NowPlayingApp.printAnswer()
        exit(0)
    case "--now-playing-list"?:
        printNowPlayingList()
    case "--now-playing-reasons"?:
        printNowPlayingReasons()
    case let option? where AppQuery(rawValue: option) != nil:
        answer(AppQuery(rawValue: option)!)
    default:
        break
    }

    // Now Playing, shown for a press while the user hid it, put back should
    // an earlier check or press have ended meanwhile (not by a one-line
    // answer: the fresh copy a press asks for Now Playing would undo it).
    NowPlayingSetting.restoreIfLeft(defaults: nowPlayingRecord)
    // A check (or, with --read-only, the same without pressing anything), or
    // a press (--play, --pause): each step in the report's order.
    startRun()
    watchForStops()
    reportScripting()
    if testing { checkPermissions() }
    reportMenu()
    reportSound()
    firstStateThenPage()
    if testing {
        runPressTest()
        unmuteAfterTest()
    }
    if let action { press(action) }
    reportWays()
    reportVerdict()
    writeResult()
    reportSwitchesBack()
}
