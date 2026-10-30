import Testing
@testable import ScriptablePlayers
@testable import PlayerCheckKit

@Suite("PlayerKindVerdict")
struct PlayerKindVerdictTests {
    /// What only a developer's lines name: AutoHush's own types and tools.
    static let developerWords = ["Profile", "fourCharCode", "ScriptablePlayers", "PolledStateObserver", "stateNotification",
                                 "measure-volume-curve", "SupportedPlayers", "WebAppPlayers", "<App>Support"]

    /// A dictionary as a scriptable player's: pause and play in its suite,
    /// `player state` with its values, a volume.
    static var scriptable: ScriptingDictionary {
        var dictionary = ScriptingDictionary()
        dictionary.commands = ["abcdPaus": "pause", "abcdPlay": "play"]
        dictionary.properties = ["pPlS": "player state", "pVol": "sound volume"]
        dictionary.enumerators = ["kPSS", "kPSP", "kPSp"]
        return dictionary
    }

    /// One that toggles, with a `playing` flag: scriptable in a way of its own.
    static var toggling: ScriptingDictionary {
        var dictionary = ScriptingDictionary()
        dictionary.commands = ["wxyz0001": "play"]
        dictionary.properties = ["AAPL": "playing", "AACT": "current time"]
        return dictionary
    }

    /// Facts for every branch of the verdict that has developer lines.
    static var everyKind: [PlayerKindVerdict.Facts] {
        var webApp = PlayerKindVerdict.Facts(bundleID: "com.apple.Safari.WebApp.ABC")
        webApp.isSafariWebApp = true
        let notifications: [PlayerKindVerdict.StateNotification] = [.notFollowed, .announced("com.example.player.playerInfo"),
                                                                    .seen(["com.example.player.playerInfo"]), .noneSeen]
        let scriptable = notifications.map { notification in
            var facts = PlayerKindVerdict.Facts(bundleID: "com.example.player")
            facts.scripting = Self.scriptable
            facts.stateNotification = notification
            return facts
        }
        var menu = PlayerKindVerdict.Facts(bundleID: "com.example.player")
        menu.menuTitle = "Controls"
        menu.menuResult = .worked
        menu.scripting = toggling
        var ownKind = PlayerKindVerdict.Facts(bundleID: "com.example.player")
        ownKind.scripting = toggling
        return [webApp, menu, ownKind] + scriptable
    }

    @Test("without --developer, no line names AutoHush's own types; with it, they come too, after the same lines")
    func developerLinesOnlyWithTheFlag() {
        for facts in Self.everyKind {
            let user = PlayerKindVerdict.lines(facts, developer: false)
            let developer = PlayerKindVerdict.lines(facts, developer: true)
            #expect(!user.isEmpty)
            for line in user {
                #expect(!Self.developerWords.contains { line.contains($0) }, "“\(line)”")
            }
            #expect(developer.count > user.count, "\(facts.bundleID): no developer line")
            #expect(developer.filter(user.contains) == user)
            #expect(developer.contains { line in Self.developerWords.contains { line.contains($0) } })
        }
    }

    @Test("a scriptable player is told so in the supported players' words, its profile only for a developer; a scripted pause or play that didn't take is said")
    func scriptablePlayer() {
        var facts = PlayerKindVerdict.Facts(bundleID: "com.example.player")
        facts.scripting = Self.scriptable
        facts.scriptResult = .worked
        #expect(PlayerKindVerdict.lines(facts, developer: false) == [
            "  A scriptable player, as the supported scriptable players are: its own pause and play, and its state.",
            "  It has a volume, so it can fade.",
        ])
        #expect(PlayerKindVerdict.lines(facts, developer: true).contains(
            "  As a built-in player: a ScriptablePlayerProfile with suite fourCharCode(\"abcd\")."))
        // measure-volume-curve measures built-in players only.
        #expect(PlayerKindVerdict.lines(facts, developer: true).contains(
            "  Once it's built in, measure its volume's curve: swift run measure-volume-curve com.example.player."))
        // Its state found wrong (Apple TV's): said, and no profile offered.
        facts.scriptStateWrong = true
        #expect(PlayerKindVerdict.lines(facts, developer: false).first?.contains("its state by script is wrong") == true)
        #expect(!PlayerKindVerdict.lines(facts, developer: true).contains { $0.contains("ScriptablePlayerProfile") })
        facts.scriptStateWrong = false
        facts.scriptResult = .didNotPause
        #expect(PlayerKindVerdict.lines(facts, developer: false).last
            == "  But its scripted pause didn't take: check it by hand before building on it.")
        facts.scriptResult = .pausedOnly
        #expect(PlayerKindVerdict.lines(facts, developer: false).last
            == "  But its scripted play didn't bring it back: check it by hand before building on it.")
    }

    /// Facts whose verdict has nothing for a developer to build on, each
    /// with its first line.
    static var withoutDeveloperLines: [(facts: PlayerKindVerdict.Facts, first: String)] {
        func facts(_ set: (inout PlayerKindVerdict.Facts) -> Void = { _ in }) -> PlayerKindVerdict.Facts {
            var facts = PlayerKindVerdict.Facts(bundleID: "com.example.player")
            set(&facts)
            return facts
        }
        return [
            (facts(), "  Neither scriptable nor with a playback menu: AutoHush can't control it. If it has a website, try that as a Safari web app."),
            (facts { $0.pageHasPlayPause = true }, "  Neither scriptable nor with a playback menu."),
            // Its row in the Now Playing panel worked; one that didn't changes nothing.
            (facts { $0.panelResult = .worked },
             "  Neither scriptable nor with a playback menu, but its row in the Now Playing panel plays and pauses it."),
            (facts { $0.panelResult = .didNotPause },
             "  Neither scriptable nor with a playback menu: AutoHush can't control it. If it has a website, try that as a Safari web app."),
            (facts { $0.isRunning = false }, "  No usable scripting; open it and run again to look for a playback menu and a page."),
            // Any Chromium browser's, named so; its sound is its own browser's.
            (facts { $0.webAppBrowser = "Brave Browser" }, "  A Chromium web app. Its sound is Brave Browser's, shared with its tabs:"),
            (facts { $0.menuTitle = "Controls"; $0.menuResult = .pausedOnly },
             "  Its menu paused it, but pressing it again didn't play it: check it by hand before building on it."),
            (facts { $0.menuTitle = "Controls"; $0.menuResult = .didNotPause },
             "  Its menu has Play/Pause, but pressing it didn't take: not controllable that way."),
            (facts { $0.menuTitle = "Controls" },
             "  Probably a menu player, as the supported menu players are (menu “Controls”): confirm by testing it while it plays."),
        ]
    }

    @Test("with nothing for a developer to build on (no kind, a page only, a browser's web app, a menu…), the verdict is the same with --developer")
    func noKind() {
        for (facts, first) in Self.withoutDeveloperLines {
            let lines = PlayerKindVerdict.lines(facts, developer: false)
            #expect(PlayerKindVerdict.lines(facts, developer: true) == lines)
            #expect(lines.first == first)
        }
    }
}
