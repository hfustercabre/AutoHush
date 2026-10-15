import Testing
import ScriptablePlayers
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

    @Test("a scriptable player is told so in the supported players' words, its profile only for a developer")
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
    }

    @Test("an app neither scriptable nor with a menu has no developer line")
    func noKind() {
        var facts = PlayerKindVerdict.Facts(bundleID: "com.example.player")
        facts.isRunning = true
        #expect(PlayerKindVerdict.lines(facts, developer: true) == PlayerKindVerdict.lines(facts, developer: false))
        #expect(PlayerKindVerdict.lines(facts, developer: false).first?.contains("AutoHush can't control it") == true)
    }
}
