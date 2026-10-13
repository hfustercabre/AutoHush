// playercheck: could AutoHush control this app as a player, and how? It
// reads the app's scripting dictionary, its playback menu, where its sound
// comes from, whether it holds Now Playing and the buttons of its page (a
// web page in its windows, a Safari web app's or any app's; an Electron or
// CEF app's, or a Flutter app's interface, once a switch for assistive tools
// is on), then lists the ways it could be controlled and says which kind of
// player it could be: scriptable, a menu player, or one that learns its
// page's button. Tools/PlayerCheckApp runs it from a window.
//   playercheck <app name, bundle ID or path>          checks it, and tests each way to control it: pauses
//                                                      and plays it once by each (asking for it to be
//                                                      started first when it isn't playing), with its window
//                                                      in each state a player's can be in (visible, covered,
//                                                      on another desktop, covered there, full screen,
//                                                      minimized, hidden), then puts its window back
//   playercheck <app> --block-input                    the same, blocking clicks, scrolling and keys while it moves
//                                                      the window and presses (Escape stops the check)
//   playercheck <app> --read-only                      checks it without pressing anything
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
// Each check, press or relaunch is also logged in ~/Library/Logs/PlayerCheck (the last 50).
// A target of AutoHush's package, using AutoHush's own code wherever the two
// do the same thing (Apple events, menus, learned page buttons, sound).
// Build: swift build -c release --product playercheck
import AppKit
import AutoHushKit

// Whoever reads the output may go first (Player Check quitting mid-check):
// writing then fails quietly, and a test that paused the app still plays
// it again and puts back what it changed, instead of being killed.
signal(SIGPIPE, SIG_IGN)
atexit { log("(ended)") }

MainActor.assumeIsolated {
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
    reportSwitchesBack()
}
