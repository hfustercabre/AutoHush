import AutoHushKit
import CoreGraphics
import Foundation
import Testing
@testable import PlayerCheck
import CheckedPlayers
import PlayerCheckKit
import WebAppPlayers
import AutoHushTestSupport

/// Where the tool's log and caches go while it's tested (`ReadOnlyRun`).
private let folder = testRunFolder

/// One test at a time: the tool's command line and log are its process's,
/// set once for all of them (`ReadOnlyRun`).
@Suite("playercheck", .serialized, .readOnlyRun)
@MainActor
struct PlayerCheckTests {
    @Test("its command line: the app, wherever it comes, its options and their values; a read-only run tests nothing and blocks nothing")
    func commandLine() {
        #expect(target == "/System/Applications/Calculator.app")
        #expect(appName == "Calculator" && bundleID == "com.apple.calculator" && !isWebApp)
        #expect(readOnly && !testing && action == nil && via == nil && !blockInput && !pressingOneWay && !developer)
        #expect(value(of: "--logs") == folder && RunLog.folder.path == folder && cachesFolder.path == folder)
        #expect(pressNeeds([.menu]) && forDevelopers("for developers").isEmpty)
    }

    @Test("a press by one way reads the menu and the page for their own way, or unless its scripted state shows whether it plays: its report to Now Playing doesn't spare them")
    func pressReads() {
        #expect(pressNeeds([.menu], pressingOneWay: false, via: nil, otherSigns: [.script, .report]))
        #expect(pressNeeds([.menu], pressingOneWay: true, via: .menu, otherSigns: [.script]))
        #expect(pressNeeds([.page], pressingOneWay: true, via: .page, otherSigns: [.script]))
        #expect(!pressNeeds([.menu], pressingOneWay: true, via: .panel, otherSigns: [.script, .report]))
        #expect(!pressNeeds([.page], pressingOneWay: true, via: .script, otherSigns: [.script]))
        // Its report comes after the menu and the page (`SignKind`): it's judged by them, as AutoHush judges it (K1).
        #expect(pressNeeds([.menu], pressingOneWay: true, via: .panel, otherSigns: [.report]))
        #expect(pressNeeds([.page], pressingOneWay: true, via: .script, otherSigns: [.report]))
        #expect(pressNeeds([.menu, .page, .panel], pressingOneWay: true, via: .script, otherSigns: []))
    }

    @Test("what the report writes: a button's Play or Pause word only, never what plays; menu shortcuts; script codes and errors; the switches by name")
    func words() {
        #expect(named("Pause current", ["pause"]) && named("PLAY", ["play"]) && !named("Pauses", ["pause"]))
        #expect(shown("Pause") == "“Pause”" && shown("Sweet Song") == "a name of 2 words")
        #expect(Look(menuTitle: "Pause", menuState: .playing, sounding: true, audible: true).line == "menu “Pause”, sound on, heard")
        #expect(modifierSymbols(0) == "⌘" && modifierSymbols(1) == "⇧⌘" && modifierSymbols(2 | 8) == "⌥" && modifierSymbols(4 | 1 | 8) == "⌃⇧")
        #expect(fourCharacters(0x7050_6C53) == "pPlS")
        #expect(eventError(NSError(domain: NSOSStatusErrorDomain, code: -1743)).hasPrefix("error -1743"))
        // Never the app's message, which can name what it was playing.
        #expect(eventError(NSError(domain: NSOSStatusErrorDomain, code: -1728,
                                   userInfo: [NSLocalizedFailureReasonErrorKey: "Can’t get document “Holiday.mov”."])) == "error -1728")
        #expect(switchName(manualAccessibility) == "Electron's switch")
        #expect(switchName(enhancedUserInterface, of: .chromiumWebApp(browserID: "com.google.Chrome", browser: "Google Chrome"))
            == "Google Chrome's VoiceOver switch")
        #expect(switchName(enhancedUserInterface, of: nil) == "VoiceOver's switch")
    }

    @Test("why a trial failed: what its press said, else what the trial saw; why no Now Playing row was the app's")
    func whyItFailed() {
        #expect(whyFailed(.menu, in: .covered, .pausedOnly) == "it paused, but didn't play again")
        #expect(whyFailed(.menu, in: .covered, .didNotPause) == "pressing it changed nothing")
        trialProblem = "no button to press"
        defer { trialProblem = nil }
        #expect(whyFailed(.menu, in: .visible, .didNotPause) == "no button to press")
        #expect(noRowProblem(rows: 0, mine: 0) == "the panel showed no rows")
        #expect(noRowProblem(rows: 3, mine: 2, showing: "Pause").hasPrefix("2 of the panel's rows with Pause show Calculator's song"))
    }

    @Test("an app's hidden interface, as its bundle tells it; the app found by its path, bundle ID or name; a page's word by the tool's lists")
    func apps() throws {
        let apps = URL(filePath: folder).appending(path: "Apps")
        func app(_ name: String, framework: String? = nil, version: String? = nil, info: [String: String] = [:]) throws -> URL {
            try TestAppBundle.make(in: apps, name: name, info: info, frameworks: framework.map { [$0] } ?? [], frameworkVersion: version)
        }
        let plain = try app("Plain")
        #expect(HiddenInterface.of(plain) == nil)
        #expect(HiddenInterface.of(try app("Electron", framework: "Electron Framework", version: "38.4.0"))?.name == "Electron 38.4.0")
        #expect(HiddenInterface.of(try app("CEF", framework: "Chromium Embedded Framework"))?.name == "Chromium (CEF)")
        #expect(HiddenInterface.of(try app("Flutter", framework: "FlutterMacOS"))?.name == "Flutter")
        let web = HiddenInterface.of(try app("Web", info: ["CrAppModeShortcutURL": "http://localhost/", "CrBundleIdentifier": "com.example.browser"]))
        guard case .chromiumWebApp(let browserID, let browser)? = web else { Issue.record("not a web app: \(String(describing: web))"); return }
        #expect(browserID == "com.example.browser" && browser == "com.example.browser") // a browser not installed: its ID
        #expect(web?.switches == PageAccess.switches(for: .chromiumWebApp(browserID: "com.example.browser")))

        #expect(findApp(plain.path)?.path == plain.path)
        #expect(findApp("com.apple.calculator")?.lastPathComponent == "Calculator.app")
        #expect(findApp("Calculator")?.path == "/System/Applications/Calculator.app")
        #expect(findApp("No Such App 4711") == nil)
        #expect(wordSays("Pause") == .playing && wordSays("Play") == .paused && wordSays("Shuffle") == nil)
    }

    /// One test, not one per clause: each run started writes a log of its own and trims the folder again.
    @Test("the run's log: named by the app and the run, every line with the home folder as ~, its oldest beyond 50 to the Trash, no other")
    func logFile() throws {
        // Noted instead of moved to the Trash: the test's folder goes at the end, the Trash wouldn't.
        let discarded = Locked<[String]>([])
        let discard = runLog.discard
        defer { runLog.discard = discard }
        runLog.discard = { url in discarded.append(url.lastPathComponent) }
        let logs = URL(filePath: folder)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for index in 0..<51 {
            #expect(FileManager.default.createFile(atPath: logs.appending(path: "2000-01-01 00.00.\(String(format: "%02d", index)).000 Old check.log").path, contents: nil))
        }
        // Another app's logs, older by their names: never trimmed.
        let others = ["1999-12-31 23.59.59.000 Other.log", "1999 other.log", "app.log"]
        for name in others { #expect(FileManager.default.createFile(atPath: logs.appending(path: name).path, contents: nil)) }
        startRun()
        say("music in \(NSHomeDirectory())/Music")
        #expect(discarded.value == ["2000-01-01 00.00.00.000 Old check.log", "2000-01-01 00.00.01.000 Old check.log"])
        let all = try FileManager.default.contentsOfDirectory(atPath: folder)
        #expect(others.allSatisfy(all.contains))
        let names = all.filter(RunLogName.isRunLog).sorted()
        #expect(names.count == RunLog.kept + 2) // the two noted, still there
        let newest = try #require(names.last)
        #expect(newest.hasSuffix(" Calculator read-only.log"))
        let text = try String(contentsOfFile: logs.appending(path: newest).path, encoding: .utf8)
        #expect(text.contains("Calculator ") && text.contains("music in ~/Music") && !text.contains(NSHomeDirectory()))
    }
    @Test("a trial: paused and played again, it works; not paused, the press is undone; a play that took late, only when pressed again, or not at all works only half; a track that ended meanwhile says so")
    func trialVerdicts() {
        let playing = Look(state: .playing, sounding: true), paused = Look(state: .paused, sounding: false)
        let stopped = Look(state: .stopped, sounding: false)
        /// A trial on `looks`, what the app shows at each look or wait in turn.
        func run(_ looks: [Look], sends: Bool = true) -> (result: TrialResult, undone: Bool, problem: String?, ended: Bool) {
            trialProblem = nil
            var shown = looks, undone = false
            func next() -> Look { shown.count > 1 ? shown.removeFirst() : shown[0] }
            let result = trial("a test", pid: 1, pause: { _ in sends }, play: { _ in true }, undo: { undone = true },
                               reading: TrialReading(look: { _, _ in next() }, waitFor: { _, _, _, _ in next() }))
            return (result, undone, trialProblem, trialTrackEnded)
        }
        #expect(run([playing, paused, playing]).result == .worked)
        let notPaused = run([playing, playing])
        #expect(notPaused.result == .didNotPause && notPaused.undone)
        #expect(run([playing], sends: false).result == .didNotPause)
        let late = run([playing, paused, paused, playing]) // played again only by the next look
        #expect(late.result == .pausedOnly && late.problem?.contains("only after more than 4 s") == true)
        let twice = run([playing, paused, paused, paused, playing])
        #expect(twice.result == .pausedOnly && twice.problem?.contains("only when pressed a second time") == true)
        let neither = run([playing, paused, paused, paused, paused])
        #expect(neither.result == .pausedOnly && neither.problem == nil && !neither.ended)
        let ended = run([playing, paused, stopped])
        #expect(ended.result == .pausedOnly && ended.ended)
    }

    @Test("a window is covered only when the windows above it hold every point of a 9×9 grid over it, edges included, within half a point")
    func covered() {
        let box = CGRect(x: 100, y: 100, width: 400, height: 300)
        let left = CGRect(x: 100, y: 100, width: 200, height: 300), right = CGRect(x: 300, y: 100, width: 200, height: 300)
        #expect(WindowStates.isCovered(box: box, above: [box]))
        #expect(WindowStates.isCovered(box: box, above: [box.insetBy(dx: 0.4, dy: 0.4)])) // within half a point
        #expect(!WindowStates.isCovered(box: box, above: [box.insetBy(dx: 1, dy: 1)])) // its edges show
        #expect(WindowStates.isCovered(box: box, above: [left, right]))
        #expect(!WindowStates.isCovered(box: box, above: [left]))
        #expect(!WindowStates.isCovered(box: box, above: []))
    }

    @Test("an ordinary window: a document window's layer, and a standard window whatever its height, or any other at least 200 points tall")
    func ordinaryWindows() {
        #expect(WindowStates.isOrdinary(layer: 0, height: 130, isStandard: true)) // a movie player's for sound alone
        #expect(WindowStates.isOrdinary(layer: 0, height: 200, isStandard: false))
        #expect(!WindowStates.isOrdinary(layer: 0, height: 199, isStandard: false)) // a strip, a helper
        #expect(!WindowStates.isOrdinary(layer: 3, height: 600, isStandard: true))
        #expect(!WindowStates.isOrdinary(layer: nil, height: 600, isStandard: true))
    }
}
