import AutoHushKit
import Foundation
import os
import Testing
@testable import PlayerCheck
import CheckedPlayers
import PlayerCheckKit
import WebAppPlayers
import AutoHushTestSupport

/// Where the tool's log and caches go while it's tested, removed at the end.
private let folder = FileManager.default.temporaryDirectory.appending(path: "PlayerCheckTests-\(UUID().uuidString)").path

/// The tool as the tests run it: a read-only check of Calculator, with its
/// own folders. Set once, before anything reads its command line.
private let readOnlyRun: Void = {
    argumentsForTests = ["/System/Applications/Calculator.app", "--read-only", "--logs", folder, "--caches", folder]
    atexit { _ = try? FileManager.default.removeItem(atPath: folder) }
}()

/// One test at a time: the tool's command line and log are its process's,
/// set once for all of them.
@Suite("playercheck", .serialized)
@MainActor
struct PlayerCheckTests {
    init() { _ = readOnlyRun }

    @Test("its command line: the app, wherever it comes, its options and their values; a read-only run tests nothing and blocks nothing")
    func commandLine() {
        #expect(target == "/System/Applications/Calculator.app")
        #expect(appName == "Calculator" && bundleID == "com.apple.calculator" && !isWebApp)
        #expect(readOnly && !testing && action == nil && via == nil && !blockInput && !pressingOneWay && !developer)
        #expect(value(of: "--logs") == folder && RunLog.folder.path == folder && cachesFolder.path == folder)
        #expect(pressNeeds([.menu]) && forDevelopers("for developers").isEmpty)
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
        let discarded = OSAllocatedUnfairLock(initialState: [String]())
        let discard = runLog.discard
        defer { runLog.discard = discard }
        runLog.discard = { url in discarded.withLock { $0.append(url.lastPathComponent) } }
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
        #expect(discarded.withLock { $0 } == ["2000-01-01 00.00.00.000 Old check.log", "2000-01-01 00.00.01.000 Old check.log"])
        let all = try FileManager.default.contentsOfDirectory(atPath: folder)
        #expect(others.allSatisfy(all.contains))
        let names = all.filter(RunLogName.isRunLog).sorted()
        #expect(names.count == RunLog.kept + 2) // the two noted, still there
        let newest = try #require(names.last)
        #expect(newest.hasSuffix(" Calculator read-only.log"))
        let text = try String(contentsOfFile: logs.appending(path: newest).path, encoding: .utf8)
        #expect(text.contains("Calculator ") && text.contains("music in ~/Music") && !text.contains(NSHomeDirectory()))
    }
}
