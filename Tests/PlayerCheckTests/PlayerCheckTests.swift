import ApplicationServices
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

    @Test("a switch set back is said as it was: off, or on for one found on")
    func switchesSetBack() {
        #expect(switchBackLine(manualAccessibility, foundOn: false, stuck: false) == "(Electron's switch set back to off, as it was.)")
        #expect(switchBackLine(enhancedUserInterface, foundOn: true, stuck: false) == "(VoiceOver's switch set back to on, as it was.)")
        #expect(switchBackLine(enhancedUserInterface, foundOn: true, stuck: true) == "(Couldn't set VoiceOver's switch back to on.)")
        #expect(switchBackLine(manualAccessibility, foundOn: false, stuck: true) == "(Couldn't set Electron's switch back to off.)")
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

    @Test("a log line that can't be written is left out, and the run goes on (no exception under the log's lock)")
    func logLineNotWritten() throws {
        let log = RunLog()
        log.discard = { _ in } // the other tests' logs stay
        let app = "Unwritable \(UUID().uuidString)"
        log.start(app: app, doing: RunLogName.doing(nil, via: nil, readOnly: true))
        // Its file found by its open descriptor, which is then made read-only: every write fails.
        func openPath(of descriptor: Int32) -> String? {
            var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        let descriptor = try #require((0..<getdtablesize()).first { openPath(of: $0)?.hasSuffix(" \(app) read-only.log") == true })
        let path = try #require(openPath(of: descriptor))
        defer { try? FileManager.default.removeItem(atPath: path) } // not counted with the other tests' logs
        let readOnly = open("/dev/null", O_RDONLY)
        defer { close(readOnly) }
        #expect(dup2(readOnly, descriptor) == descriptor)
        log.write("a line it can't write")
        #expect(try !String(contentsOfFile: path, encoding: .utf8).contains("a line it can't write"))
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

    @Test("a window whose green button only zooms can't go full screen; one with a full screen button, or neither, is tried")
    func fullScreenByButtons() {
        #expect(!WindowTest.canGoFullScreen(buttonSubroles: [kAXCloseButtonSubrole, kAXZoomButtonSubrole, kAXMinimizeButtonSubrole, nil]))
        #expect(WindowTest.canGoFullScreen(buttonSubroles: [kAXCloseButtonSubrole, kAXFullScreenButtonSubrole, kAXMinimizeButtonSubrole]))
        #expect(WindowTest.canGoFullScreen(buttonSubroles: [nil, nil]))
    }

    @Test("with its windows closed, a way's one run is its line's, saying so, and the window states it wasn't tested in follow under it")
    func windowsClosedSummary() throws {
        let note = TestScope.windowStatesNote
        defer {
            TestResults.byState = [:]
            TestScope.windowStatesNote = note
        }
        #expect(TestScope.windowTest == nil)
        TestScope.windowStatesNote = TestScope.noWindowOpen
        TestResults.byState[.panel] = [(.windowsClosed, .worked, "")]
        let worked = try #require(stateSummary(.panel))
        #expect(worked.mark == .works && worked.suffix == " (with its windows closed)")
        #expect(worked.lines == [CheckReportLine.wayState(.notChecked, "window states", "not tested (no window open)")])
        TestResults.byState[.panel] = [(.windowsClosed, .pausedOnly, "it paused, but didn't play again")]
        #expect(stateSummary(.panel)?.mark == CheckReportLine.WayMark.none)
        #expect(stateSummary(.menu) == nil) // not tried
    }

    @Test("the verdict judges a way by every window state it was tried in, as its line does: it works when it worked in any, though not in the first; else it paused only when it paused in any; with no states, by its only run")
    func overallResult() {
        defer {
            TestResults.first = [:]
            TestResults.byState = [:]
        }
        // Not pressed in view (no button in sight), pressed in the other states (L2, 2026-10-30).
        TestResults.first[.page] = .didNotPause
        TestResults.byState[.page] = [(.visible, .didNotPause, "its page showed no Play/Pause to press"), (.covered, .worked, ""), (.hidden, .worked, "")]
        #expect(TestResults.overall(.page) == .worked)
        TestResults.byState[.page] = [(.visible, .didNotPause, ""), (.covered, .pausedOnly, "it paused, but didn't play again")]
        #expect(TestResults.overall(.page) == .pausedOnly)
        TestResults.byState[.page] = [(.visible, .didNotPause, ""), (.covered, .didNotPause, "")]
        #expect(TestResults.overall(.page) == .didNotPause)
        TestResults.byState = [:]
        TestResults.first[.page] = .worked
        #expect(TestResults.overall(.page) == .worked)
        #expect(TestResults.overall(.menu) == nil) // not tried
    }
}
