import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerOption")
@MainActor
struct PlayerOptionTests {
    @Test("every player in the catalog is offered, in its order, with where it's installed and its placeholder, drawn while it isn't")
    func list() {
        let placeholder = PlayerIconPlaceholder(tile: [.init(0x000000)], mark: .init(0x1ED760)) { CGMutablePath() }
        let catalog = MusicPlayerCatalog(players: [
            MockMusicPlayer(bundleID: "com.example.first", name: "First", iconPlaceholder: placeholder),
            MockMusicPlayer(bundleID: "com.example.second", name: "Second"),
        ])
        let url = URL(fileURLWithPath: "/Applications/Second.app")
        let options = PlayerOption.list(catalog) { $0 == "com.example.second" ? url : nil }

        #expect(options == [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: nil),
            PlayerOption(bundleID: "com.example.second", name: "Second", appURL: url),
        ])
        #expect(options.map(\.isInstalled) == [false, true])
        #expect(options[0].iconPlaceholder?.mark == placeholder.mark)
        #expect(options[1].iconPlaceholder == nil)
        #expect(drawsSomething(options[0].icon(size: 32)))
    }

    @Test("players are offered installed first, then the others, each in the catalog's order")
    func installedFirst() {
        let options = [option("A", installed: false), option("B", installed: true), option("C", installed: false),
                       option("D", installed: true)]
        #expect(options.offered.map(\.name) == ["B", "D", "A", "C"])
        #expect(options.filter(\.isInstalled).offered.map(\.name) == ["B", "D"])
    }

    @Test("Safari web apps come after every app, under their heading")
    func webAppsLast() {
        var webApp = option("YT Music", installed: true)
        webApp.kind = .safariWebApp
        let options = [webApp, option("A", installed: false), option("B", installed: true)]
        #expect(options.offered.map(\.name) == ["B", "A", "YT Music"])
        #expect(!PlayerOption.webAppsHeading.isEmpty)
        #expect(PlayerOption.experimentalBadge == "Experimental")
        #expect(PlayerOption.webAppsWarning.hasPrefix("Experimental:"))
    }

    @Test("apps added through a check come after the supported apps and before the web apps, under their heading")
    func checkedAppsBetween() {
        var webApp = option("YT Music", installed: true)
        webApp.kind = .safariWebApp
        var checked = option("Deezer", installed: true)
        checked.kind = .checkedApp
        let options = [webApp, checked, option("A", installed: false), option("B", installed: true)]
        #expect(options.offered.map(\.name) == ["B", "A", "Deezer", "YT Music"])
        #expect(PlayerOption.checkedByYouBadge == "Checked by you")
        #expect(PlayerOption.addAppTitle == "Add an App…")
    }

    @Test("an app added through a check that isn't installed now stays under Other Apps, after the installed ones, dimmed: it can't be clicked")
    func uninstalledCheckedApp() {
        var gone = option("Gone", installed: false)
        gone.kind = .checkedApp
        var deezer = option("Deezer", installed: true)
        deezer.kind = .checkedApp
        var webApp = option("YT Music", installed: true)
        webApp.kind = .safariWebApp
        let options = [gone, webApp, deezer, option("A", installed: true)]
        #expect(options.offered.map(\.name) == ["A", "Deezer", "Gone", "YT Music"])
        #expect(!gone.isInstalled && !gone.isClickable && gone.webAddress == nil)
        #expect(deezer.isClickable)
    }

    /// A player, an app that can only be muted, one paused another way, a
    /// suggested web app, and one controlled through a Now Playing row that
    /// doesn't follow it (Qobuz's): only its sound tells.
    private func antiDotOptions() -> (all: [PlayerOption], muted: PlayerOption, soundOnly: PlayerOption) {
        var muted = option("Muted", installed: true)
        muted.kind = .checkedApp
        muted.pausesByMuting = true
        muted.needsAudioLevels = true
        var paused = option("Paused", installed: true)
        paused.kind = .checkedApp
        var soundOnly = option("Qobuz", installed: true)
        soundOnly.kind = .checkedApp
        soundOnly.needsAudioLevels = true
        let suggestion = PlayerOption.suggestion(WebAppSuggestion(name: "Deezer", address: "deezer.com"))
        return ([option("A", installed: true), muted, paused, suggestion, soundOnly], muted, soundOnly)
    }

    @Test("in AntiDot mode, an app only its sound tells (muted only, or a Now Playing row that doesn’t follow it) can’t be chosen; other players can")
    func antiDotMode() {
        let antiDot = antiDotOptions().all.inAntiDotMode(true)
        #expect(antiDot.map(\.isUnavailableInAntiDotMode) == [false, true, false, false, true])
        #expect(antiDot.map(\.isClickable) == [true, false, true, true, false])
        #expect(antiDot[1].isInstalled) // still installed, and shown as chosen
    }

    @Test("out of AntiDot mode, the apps only their sound tells can be chosen")
    func antiDotModeOff() {
        let options = antiDotOptions().all
        #expect(options.inAntiDotMode(true).inAntiDotMode(false) == options)
        #expect(options.inAntiDotMode(false).map(\.isClickable) == [true, true, true, true, true])
    }

    @Test("an app that can't be chosen in AntiDot mode says so, and why")
    func antiDotModeReasons() {
        let (_, muted, soundOnly) = antiDotOptions()
        #expect(PlayerOption.antiDotModeLabel == "Not in AntiDot mode")
        #expect(PlayerOption.antiDotModeTileLabel == "Not in AntiDot")
        #expect(muted.antiDotModeReason
            == "AutoHush can only mute it, and muting needs Audio Recording, which AntiDot mode doesn’t use.")
        #expect(soundOnly.antiDotModeReason
            == "It needs Audio Recording, which AntiDot mode doesn’t use.")
    }

    @Test("an app that can only be muted says so in a short line on its tile and a longer one on its menu row")
    func mutedLabels() {
        #expect(PlayerOption.mutedOnlyLabel == "Muted only")
        #expect(PlayerOption.mutedInsteadLabel == "Muted instead of paused")
        #expect(PlayerOption.mutedOnlyLabel.count <= 12)
        #expect(PlayerOption.antiDotModeTileLabel.count <= 14)
    }

    @Test("VoiceOver says a web app is one only when an app has its name")
    func spokenName() {
        let app = PlayerOption(bundleID: "com.example.spotify", name: "Spotify", appURL: URL(fileURLWithPath: "/Applications/Spotify.app"))
        var webApp = option("spotify", installed: true)
        webApp.kind = .safariWebApp
        var other = option("YT Music", installed: true)
        other.kind = .safariWebApp
        let options = [app, webApp, other]
        #expect(webApp.spokenName(among: options) == "spotify, Safari web app")
        #expect(app.spokenName(among: options) == "Spotify")
        #expect(other.spokenName(among: options) == "YT Music")
        #expect(webApp.spokenName(among: [webApp, other]) == "spotify")
    }

    @Test("VoiceOver says whose web app an app added through a check is, when a Chromium browser made it, as its icon's badge shows")
    func spokenBrowserWebApp() {
        var chromeApp = option("SoundCloud", installed: true)
        chromeApp.kind = .checkedApp
        chromeApp.browserName = "Google Chrome"
        var plain = option("Deezer", installed: true)
        plain.kind = .checkedApp
        let options = [chromeApp, plain]
        #expect(chromeApp.spokenName(among: options) == "SoundCloud, Google Chrome web app")
        #expect(plain.spokenName(among: options) == "Deezer")
        var unbadged = chromeApp
        unbadged.browserName = nil
        #expect(chromeApp != unbadged) // the browser tells them apart
    }

    @Test("suggested web apps come after the web apps, marked with a download symbol, and can be clicked though not installed")
    func suggestions() {
        let catalog = MusicPlayerCatalog(
            players: [MockMusicPlayer(bundleID: "com.example.first", name: "First")],
            found: { [MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.A", name: "YT Music", status: .learned)] },
            suggested: { [WebAppSuggestion(name: "Deezer", address: "deezer.com")] }
        )
        let options = PlayerOption.list(catalog) { $0.hasPrefix("com.") ? URL(fileURLWithPath: "/Applications/\($0).app") : nil }
        #expect(options.offered.map(\.name) == ["First", "YT Music", "Deezer"])
        let deezer = options[2]
        #expect(deezer.bundleID == PlayerOption.suggestionID("deezer.com"))
        #expect(deezer.webAddress == "deezer.com")
        #expect(deezer.kind == .safariWebApp)
        #expect(!deezer.isInstalled && deezer.isClickable)
        #expect(deezer.icon(size: 16).isTemplate)
        #expect(drawsSomething(deezer.icon(size: 32)))
        #expect(options.map(\.isClickable) == [true, true, true])
        #expect(!PlayerOption(bundleID: "com.example.gone", name: "Gone", appURL: nil).isClickable)
    }

    @Test("web apps: tested sites' first, then the tested sites not added, then untested ones; suggestions don't count for the search")
    func webAppOrder() {
        let untested = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.U", name: "SoundCloud", status: .learned,
                                          installedURL: URL(fileURLWithPath: "/Users/test/Applications/SoundCloud.app"),
                                          isUntested: true)
        let tested = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.T", name: "YT Music", status: .learned,
                                        installedURL: URL(fileURLWithPath: "/Users/test/Applications/YT Music.app"))
        let catalog = MusicPlayerCatalog(
            players: (1...6).map { MockMusicPlayer(bundleID: "com.example.\($0)", name: "App \($0)") },
            found: { [untested, tested] },
            suggested: { [WebAppSuggestion(name: "Spotify", address: "open.spotify.com"),
                          WebAppSuggestion(name: "Deezer", address: "deezer.com")] }
        )
        let options = PlayerOption.list(catalog) { _ in nil } // macOS knows none: web apps say where they are
        #expect(options.offered.map(\.name).suffix(4) == ["YT Music", "Spotify", "Deezer", "SoundCloud"])
        #expect(options.first { $0.name == "SoundCloud" }?.isUntested == true)
        #expect(options.first { $0.name == "YT Music" }.map { $0.isInstalled && !$0.isUntested } == true)
        #expect(options.count == 10)
        #expect(options.isSearchable) // 6 apps and 2 web apps: 8
        #expect(!options.filter { $0.name != "SoundCloud" }.isSearchable) // the 2 suggestions don't count
        #expect(PlayerOption.untestedBadge == "Untested")
    }

    @Test("from eight players on, they can be searched by name, ignoring case and accents")
    func search() {
        let names = ["Spotify", "Apple Music", "VLC", "Apple Podcasts", "TIDAL", "Qobuz", "Música"]
        let seven = names.map { option($0, installed: true) }
        #expect(!seven.isSearchable)
        #expect((seven + [option("Deezer", installed: false)]).isSearchable)
        #expect(PlayerOption.searchThreshold == 8)

        #expect(seven.matching("").map(\.name) == names)
        #expect(seven.matching("  ").map(\.name) == names)
        #expect(seven.matching(" musi ").map(\.name) == ["Apple Music", "Música"])
        #expect(seven.matching("APPLE P").map(\.name) == ["Apple Podcasts"])
        #expect(seven.matching("zz").isEmpty)
        #expect(PlayerOption.noMatchNote("zz") == "No players match “zz”.")
    }

    private func option(_ name: String, installed: Bool) -> PlayerOption {
        PlayerOption(bundleID: "com.example.\(name.lowercased())", name: name,
                     appURL: installed ? URL(fileURLWithPath: "/Applications/\(name).app") : nil)
    }

    /// Whether `image`, drawn at 2×, leaves some pixel mostly opaque: an
    /// image drawn by a handler draws only then.
    private func drawsSomething(_ image: NSImage) -> Bool {
        let pixels = Int(image.size.width * 2)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<pixels).contains { x in (0..<pixels).contains { y in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 } }
    }

    @Test("apps count as installed only in /Applications, the user's Applications folder and /System/Applications")
    func applicationFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ApplicationFolders.all.map(\.path) == ["/Applications", "\(home)/Applications", "/System/Applications"])

        let anywhere: (URL) -> Bool = { _ in true }
        func installed(_ path: String) -> Bool {
            PlayerOption.firstInstalled([URL(fileURLWithPath: path)], exists: anywhere) != nil
        }
        #expect(installed("/Applications/Player.app"))
        #expect(installed("/Applications/Music Apps/Player.app"))
        #expect(installed("\(home)/Applications/Player.app"))
        #expect(installed("/System/Applications/Player.app"))

        #expect(!installed("\(home)/.Trash/Player.app"))
        #expect(!installed("/Volumes/Player/Player.app")) // the disk image it came from
        #expect(!installed("/Users/someone-else/Applications/Player.app"))
        #expect(!installed("\(home)/Downloads/Player.app"))
        #expect(!installed("/Applications Old/Player.app"))
    }

    @Test("the first copy in an Applications folder is the one found")
    func firstInApplicationFolders() {
        let trashed = URL(fileURLWithPath: "/Users/someone/.Trash/Player.app")
        let installed = URL(fileURLWithPath: "/Applications/Player.app")
        #expect(PlayerOption.firstInstalled([trashed, installed], exists: { _ in true }) == installed)
        #expect(PlayerOption.firstInstalled([trashed], exists: { _ in true }) == nil)
        #expect(PlayerOption.firstInstalled([], exists: { _ in true }) == nil)
    }

    @Test("an app macOS still lists but that's gone from disk doesn't count as installed")
    func deletedIsNotInstalled() {
        let deleted = URL(fileURLWithPath: "/Applications/Player.app")
        let installed = URL(fileURLWithPath: "/System/Applications/Player.app")
        #expect(PlayerOption.firstInstalled([deleted, installed]) { $0 == installed } == installed)
        #expect(PlayerOption.firstInstalled([deleted]) { _ in false } == nil)
        // The real check, against an app that is on every Mac.
        #expect(PlayerOption.firstInstalled([URL(fileURLWithPath: "/System/Applications/Music.app")]) != nil)
    }
}
