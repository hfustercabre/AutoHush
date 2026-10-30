import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension AppDelegateTests {
    // MARK: - Players that learn

    @MainActor
    @Test("choosing a web app AutoHush must learn asks for it in a window, which shows the steps and closes once learned")
    func learningWindow() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learning(hasPlayed: false))
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.learning == nil)
        #expect(sut.status.playerOptions.map(\.kind) == [.app, .safariWebApp])

        sut.choosePlayer(webApp.bundleID)
        #expect(scratch.learningWindow.isOpen)
        #expect(sut.status.learning == .learning(hasPlayed: false))
        #expect(sut.settingsModel.learning == .learning(hasPlayed: false))

        webApp.set(.learning(hasPlayed: true))
        await TestWait.until { sut.settingsModel.learning == .learning(hasPlayed: true) }

        webApp.set(.learned)
        await TestWait.until { !scratch.learningWindow.isOpen }
        #expect(sut.status.learning == .learned)
        #expect(!scratch.learningWindow.isOpen && sut.status.canLearnControlsAgain)

        sut.choosePlayer(Players.first)
        #expect(sut.status.learning == nil)
        sut.choosePlayer(webApp.bundleID) // learned already: no window
        #expect(scratch.learningWindow.shownCount == 1)
    }

    @MainActor
    @Test("Learn Again while Add a Web App adds one asks first: Cancel keeps the add, Stop Adding stops it and learns", arguments: [false, true])
    func learnAgainWhileAdding(stops: Bool) async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz",
                                                            url: URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app"), alreadyThere: false)))
        let (sut, _) = makeSUT(scratch)
        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.learning == .learned }
        let asked = CallLog()
        sut.runAlert = { alert in
            asked.calls.append(alert.messageText)
            return stops ? .alertFirstButtonReturn : .alertSecondButtonReturn
        }
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") } // waits for Add to Dock

        sut.learnControlsAgain()
        await TestWait.until { asked.calls == ["Stop Adding play.qobuz.com?"] }
        if stops {
            await TestWait.until { scratch.learningWindow.isOpen && !scratch.addWindow.isOpen }
        } else {
            #expect(scratch.addWindow.isOpen && sut.addWebApp.adding != nil && !scratch.learningWindow.isOpen)
            sut.addWebApp.close()
        }
    }

    @MainActor
    @Test("Learn Again's Stop Adding, once Add a Web App's web app is made and looked for, stops the add: listed later, it isn't chosen")
    func learnAgainStopsAddOnceMade() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        let url = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        let made = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learned, installedURL: url)
        let found = scratch.webAppsFound
        found.value = [webApp] // macOS doesn't list the one made yet
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.value })
        scratch.installed.insert(made.bundleID)
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: made.bundleID, name: "Qobuz", url: url, alreadyThere: true)))
        let (sut, _) = makeSUT(scratch, madeWebAppWait: .milliseconds(200))
        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.learning == .learned }
        sut.runAlert = { _ in .alertFirstButtonReturn } // Stop Adding
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.madeBundleID == made.bundleID } // made: looked for until listed
        let adding = sut.addWebApp.adding

        sut.learnControlsAgain()
        await TestWait.until { scratch.learningWindow.isOpen }
        found.value = [webApp, made] // listed now: a look still under way would choose it
        await adding?.value
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        #expect(sut.addWebApp.adding == nil)
    }

    @MainActor
    @Test("an add cancelled while its web app just made waits to be looked for again doesn't choose it, though it's listed by then")
    func cancelledWhileLookingForWebApp() async {
        let scratch = Scratch()
        let (webApp, _) = scratch.makesWebApp(named: "Qobuz", status: .learned)
        scratch.maker.onMake = {} // macOS doesn't list it yet
        let (sut, _) = makeSUT(scratch, madeWebAppWait: .seconds(30))
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebApp.model.addTapped()
        await TestWait.until { !scratch.opened.isEmpty } // made and opened: chosen once, then looked for again
        try? await Task.sleep(for: .milliseconds(50)) // its next look, half a minute away
        let adding = sut.addWebApp.adding

        scratch.webAppsFound.value = [webApp] // listed now
        sut.addWebApp.cancel() // the window's Cancel: the wait ends at once
        await adding?.value
        #expect(sut.status.chosenPlayerID == Players.first)
    }

    @MainActor
    @Test("a web app's controls are learned afresh in a new window, which replaces an open one; closed before It's Playing, what it learned stays")
    func learnControlsAgain() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        let (sut, _) = makeSUT(scratch)
        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.learning == .learned }
        #expect(!scratch.learningWindow.isOpen)
        #expect(sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.canLearnControlsAgain)

        sut.learnControlsAgain()
        await TestWait.until { scratch.learningWindow.isOpen && sut.status.learning == .relearning }
        #expect(webApp.learnAgainCount == 1)
        #expect(scratch.learningWindowsMade == 1)
        #expect(sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.learning == .relearning) // still learned: the Controls row says so

        // Later, or the close button, before It's Playing: what it learned stays.
        scratch.learningWindow.close()
        await TestWait.until { sut.status.learning == .learned }
        #expect(webApp.keepLearnedCount == 1)

        // Again, and It's Playing taken (the player forgets then); then again
        // while the window is open: it closes, a new one starts over, and
        // closing the old one keeps nothing.
        sut.learnControlsAgain()
        await TestWait.until { scratch.learningWindow.isOpen && sut.status.learning == .relearning }
        webApp.set(.learning(hasPlayed: true))
        await TestWait.until { sut.settingsModel.learning == .learning(hasPlayed: true) }
        sut.learnControlsAgain()
        #expect(!scratch.learningWindow.isOpen) // the old one, closed at once
        // The new window and the player's new status come by separate tasks, in either order.
        await TestWait.until { scratch.learningWindow.isOpen && sut.settingsModel.learning == .learning(hasPlayed: false) }
        #expect(webApp.learnAgainCount == 3)
        #expect(scratch.learningWindowsMade == 3)
        #expect(webApp.keepLearnedCount == 1)
        #expect(sut.settingsModel.learning == .learning(hasPlayed: false))

        sut.choosePlayer(Players.first) // a player that learns nothing
        #expect(!sut.status.canLearnControlsAgain)
        #expect(!sut.settingsModel.canLearnControlsAgain)
    }

    @MainActor
    @Test("learning a web app's controls opens it when it isn't running, as adding it does; a running one is left as it is")
    func learningOpensWebApp() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        let (sut, _) = makeSUT(scratch)
        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.learning == .learned }
        #expect(scratch.opened.isEmpty)

        sut.learnControlsAgain()
        await TestWait.until { scratch.learningWindow.isOpen && scratch.opened.count == 1 }
        #expect(scratch.opened.count == 1)

        scratch.learningWindow.close()
        scratch.running.insert(webApp.bundleID)
        sut.learnControlsAgain()
        await TestWait.until { scratch.learningWindow.isOpen }
        // Closed again, and not running: opened, after any open the running
        // one could have asked for, which would make it three.
        scratch.learningWindow.close()
        scratch.running.remove(webApp.bundleID)
        sut.learnControlsAgain()
        await TestWait.until { scratch.opened.count >= 2 }
        #expect(scratch.opened.count == 2) // running: not opened again
    }

    @MainActor
    @Test("learning again closes Add a Web App, which floats in the same corner, whatever its step")
    func learnAgainClosesAdd() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        let (sut, _) = makeSUT(scratch)
        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.learning == .learned }
        sut.addWebApp.show() // another site's address being typed
        #expect(scratch.addWindow.isOpen)

        sut.learnControlsAgain()
        #expect(!scratch.addWindow.isOpen)
        await TestWait.until { scratch.learningWindow.isOpen }
    }

    @MainActor
    @Test("learning again, the window closed while the web app's button was missing still keeps what it learned")
    func keepLearnedWhileButtonMissing() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learned)
        let (sut, _) = makeSUT(scratch)
        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.learning == .learned }
        sut.learnControlsAgain()
        await TestWait.until { scratch.learningWindow.isOpen && sut.status.learning == .relearning }

        webApp.set(.learning(hasPlayed: false)) // its button went missing meanwhile
        await TestWait.until { sut.status.learning == .learning(hasPlayed: false) }
        scratch.learningWindow.close() // Later
        await TestWait.until { webApp.keepLearnedCount == 1 } // the player decides: it was learning again
    }

    @MainActor
    @Test("while a permission is missing, the learning window asks for it first, and the card's Controls row stays")
    func learningWaitsForPermission() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learning(hasPlayed: false))
        let (sut, _) = makeSUT(scratch)
        sut.session.launch()

        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.health == .needsPermission(.accessibility(player: "YT Music")) }
        #expect(scratch.learningWindow.isOpen) // with the permission as its first step
        #expect(sut.status.canLearnControlsAgain) // the card's Controls row stays

        webApp.setFailVerify(nil) // allowed: the retry starts monitoring
        await TestWait.until { sut.status.health == .ready }
        #expect(sut.settingsModel.learning == .learning(hasPlayed: false))
        #expect(scratch.learningWindow.shownCount == 1)
    }

    @MainActor
    @Test("a web app that isn't running yet still opens the learning window, which says to play it")
    func learningWindowForPlayerNotRunning() async {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learning(hasPlayed: false))
        webApp.setFailVerify(.playerNotRunning)
        let (sut, _) = makeSUT(scratch)
        sut.session.launch()

        sut.choosePlayer(webApp.bundleID)
        await TestWait.until { sut.status.health == .playerClosed("YT Music isn’t running") }
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("a web app added from its address is chosen and opened, its steps shown in the add window, which closes once learned")
    func addWebApp() async {
        let scratch = Scratch()
        let (webApp, appURL) = scratch.makesWebApp(named: "Qobuz")
        let (sut, _) = makeSUT(scratch)

        sut.addWebApp.show()
        #expect(scratch.addWindow.isOpen)
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") }
        #expect(scratch.webAppsFound.value.isEmpty) // nothing's added before the user clicks Add to Dock
        sut.addWebApp.model.addTapped()
        await TestWait.until { sut.status.chosenPlayerID == webApp.bundleID && !scratch.opened.isEmpty }
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        #expect(sut.addWebApp.model.phase == .learning(name: "Qobuz", alreadyThere: false))
        #expect(scratch.opened == [appURL])
        #expect(!scratch.learningWindow.isOpen) // the add window shows the steps

        webApp.set(.learned)
        await TestWait.until { !scratch.addWindow.isOpen }
    }

    /// What the user does while the add window says the web app made isn't found.
    enum WhileNotFound: CaseIterable, Sendable {
        case addressChanged, windowClosed
    }

    /// Qobuz made as a web app from the add window, which macOS doesn't list
    /// yet: looked for a few times, then said to be missing. `listNow` has
    /// macOS list it, making it again finds it there, and AutoHush looks
    /// again, as the window watch does each second meanwhile.
    @MainActor
    private func webAppNotListed() async
        -> (scratch: Scratch, sut: AppDelegate, webApp: MockLearningPlayer, listNow: @MainActor () -> Void) {
        let scratch = Scratch()
        let (webApp, appURL) = scratch.makesWebApp(named: "Qobuz")
        scratch.maker.onMake = {} // macOS doesn't list it
        let (sut, _) = makeSUT(scratch)

        sut.openAddWebApp() // the menu's Add a Web App…
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebApp.model.addTapped()
        await TestWait.until { sut.addWebApp.model.problem != nil }
        return (scratch, sut, webApp, {
            scratch.webAppsFound.value = [webApp]
            scratch.maker.result = .success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: true))
            sut.refreshPlayerOptions()
        })
    }

    @MainActor
    @Test("a web app made but not listed yet is looked for a few times; still missing, the add window says so and Continue tries again")
    func addedWebAppNotFound() async {
        let (scratch, sut, webApp, _) = await webAppNotListed()
        #expect(sut.addWebApp.model.problem == .notFound(name: "Qobuz"))
        #expect(sut.addWebApp.model.phase == .entering)
        #expect(sut.addWebApp.model.address == "play.qobuz.com") // Continue tries again
        #expect(sut.status.chosenPlayerID != webApp.bundleID)
        #expect(scratch.addWindow.isOpen)
    }

    @MainActor
    @Test("a web app made but said to be missing is added by itself once listed, which finds it there and chooses it")
    func addedWebAppFoundLater() async {
        let (_, sut, webApp, listNow) = await webAppNotListed()
        listNow()
        await TestWait.until { sut.status.chosenPlayerID == webApp.bundleID }
        #expect(sut.addWebApp.model.problem == nil)
        #expect(sut.addWebApp.model.phase == .learning(name: "Qobuz", alreadyThere: true))
    }

    @MainActor
    @Test("a web app made but said to be missing is no longer looked for once the address is changed or the window closed",
          arguments: WhileNotFound.allCases)
    func addedWebAppNoLongerLookedFor(meanwhile: WhileNotFound) async {
        let (scratch, sut, _, listNow) = await webAppNotListed()
        switch meanwhile {
        case .addressChanged: sut.addWebApp.model.address = "deezer.com"
        case .windowClosed: scratch.addWindow.close()
        }
        listNow()
        #expect(sut.addWebApp.awaitingListing == nil) // no longer looked for
        sut.refreshPlayerOptions()
        await sut.session.waitUntilIdle()
        #expect(sut.status.chosenPlayerID == Players.first)
        #expect(sut.addWebApp.model.problem == .notFound(name: "Qobuz"))
    }

    @MainActor
    @Test("a player chosen while a web app just made is looked for stays chosen, and nothing says the web app is missing")
    func playerChosenWhileLookingForWebApp() async {
        let scratch = Scratch()
        let (webApp, appURL) = scratch.makesWebApp(named: "Qobuz")
        scratch.players = MusicPlayerCatalog(players: [scratch.first, scratch.second]) // macOS doesn't list it
        scratch.maker.result = .success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: true))
        let (sut, _) = makeSUT(scratch, madeWebAppWait: .milliseconds(30))

        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.madeBundleID == webApp.bundleID }
        sut.choosePlayer(Players.second) // from the menu, meanwhile
        await TestWait.until { sut.addWebApp.adding == nil }
        #expect(sut.status.chosenPlayerID == Players.second)
        #expect(sut.addWebApp.model.problem == nil)
        #expect(!scratch.addWindow.isOpen) // its learning step would never move
    }

    @MainActor
    @Test("added from the welcome window, the add window closes: the welcome window asks for what it needs, and learning follows its Done")
    func addWebAppFromWelcome() async {
        let scratch = Scratch()
        let (webApp, _) = scratch.makesWebApp(named: "Qobuz")
        scratch.installed.remove(Players.second)
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first) // brings the welcome window
        #expect(sut.isShowingPlayerChooser)

        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebApp.model.addTapped()
        await TestWait.until { sut.status.chosenPlayerID == webApp.bundleID && !scratch.addWindow.isOpen }
        #expect(!scratch.addWindow.isOpen) // one window asks: the welcome window
        #expect(sut.isShowingPlayerChooser)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        #expect(!scratch.learningWindow.isOpen)

        sut.finishWelcome()
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("a suggested web app clicked while Add a Web App adds another asks first: Stop Adding fills it in instead, Cancel keeps the add",
          arguments: [true, false])
    func suggestedWhileAdding(stops: Bool) async {
        let scratch = Scratch()
        _ = scratch.makesWebApp(named: "Qobuz")
        scratch.players = MusicPlayerCatalog(players: [scratch.first], suggested: {
            [WebAppSuggestion(name: "Deezer", address: "deezer.com")]
        })
        let (sut, _) = makeSUT(scratch)
        let asked = CallLog()
        sut.runAlert = { alert in
            asked.calls.append(alert.messageText)
            return stops ? .alertFirstButtonReturn : .alertSecondButtonReturn
        }
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") } // waits for Add to Dock

        sut.choosePlayer(PlayerOption.suggestionID("deezer.com"))
        await TestWait.until { asked.calls == ["Stop Adding play.qobuz.com?"] }
        if stops {
            await TestWait.until { sut.addWebApp.adding == nil }
            #expect(sut.addWebApp.model.address == "deezer.com" && sut.addWebApp.model.phase == .entering && scratch.addWindow.isOpen)
        } else {
            #expect(sut.addWebApp.adding != nil && sut.addWebApp.model.address == "play.qobuz.com")
        }
        sut.addWebApp.close()
    }

    @MainActor
    @Test("a suggested web app clicked while its own site is added, typed another way, asks nothing: the add goes on")
    func suggestedWhileAddingItself() async {
        let scratch = Scratch()
        _ = scratch.makesWebApp(named: "Deezer")
        scratch.players = MusicPlayerCatalog(players: [scratch.first], suggested: {
            [WebAppSuggestion(name: "Deezer", address: "deezer.com")]
        })
        let (sut, _) = makeSUT(scratch)
        let asked = CallLog()
        sut.runAlert = { alert in
            asked.calls.append(alert.messageText)
            return .alertSecondButtonReturn
        }
        sut.addWebApp.show()
        sut.addWebApp.model.address = "https://www.deezer.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.adding != nil }
        sut.choosePlayer(PlayerOption.suggestionID("deezer.com"))
        #expect(sut.addWebApp.adding != nil && sut.addWebApp.model.address == "https://www.deezer.com")
        // An alert, on the main run loop's next turn, would have come before this.
        await withCheckedContinuation { done in RunLoop.main.perform(inModes: [.default]) { done.resume() } }
        #expect(asked.calls.isEmpty)
        sut.addWebApp.close()
    }

    @MainActor
    @Test("a suggested web app opens the add window filled in with its address, and the player stays")
    func suggestedWebApp() {
        let scratch = Scratch()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], suggested: {
            [WebAppSuggestion(name: "Deezer", address: "deezer.com")]
        })
        let (sut, _) = makeSUT(scratch)
        let suggestion = PlayerOption.suggestionID("deezer.com")
        #expect(sut.status.playerOptions.contains { $0.bundleID == suggestion && $0.webAddress == "deezer.com" })

        sut.choosePlayer(suggestion)
        #expect(scratch.addWindow.isOpen)
        #expect(sut.addWebApp.model.address == "deezer.com")
        #expect(sut.addWebApp.model.phase == .entering)
        #expect(sut.status.chosenPlayerID == Players.first)

        sut.addWebApp.model.address = "something else"
        sut.addWebApp.show() // the window's open: what's typed stays
        #expect(sut.addWebApp.model.address == "something else")
        sut.choosePlayer(suggestion) // another click fills it in again
        #expect(sut.addWebApp.model.address == "deezer.com")
    }

    @MainActor
    @Test("a web app made moments ago is chosen from where it was found, before macOS knows it")
    func addWebAppFoundWhereMade() async {
        let scratch = Scratch()
        let (webApp, appURL) = scratch.makesWebApp(named: "Qobuz", status: .learned)
        scratch.installed.remove(webApp.bundleID) // macOS doesn't know it
        let (sut, _) = makeSUT(scratch)
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebApp.model.addTapped()
        await TestWait.until { sut.status.chosenPlayerID == webApp.bundleID } // not in `scratch.installed`: macOS doesn't know it
        #expect(sut.status.playerOptions.first { $0.bundleID == webApp.bundleID }?.appURL == appURL)
    }

    @MainActor
    @Test("closing the add window while it waits for Add to Dock cancels it: nothing is added")
    func addWebAppClosedBeforeTheClick() async {
        let scratch = Scratch()
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: "x", name: "X", url: URL(fileURLWithPath: "/x.app"),
                                                            alreadyThere: false)))
        let made = Locked(false)
        scratch.maker.onMake = { made.value = true }
        let (sut, _) = makeSUT(scratch)
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .readyToAdd(site: "play.qobuz.com") }
        let adding = sut.addWebApp.adding
        sut.addWebApp.model.windowClosed()
        #expect(sut.addWebApp.model.phase == .entering)
        await adding?.value // the cancelled add is over
        #expect(!made.value)
        #expect(scratch.opened.isEmpty)
    }

    @MainActor
    @Test("closing the add window while it adds cancels it; the next add isn't held up")
    func addWebAppCancelled() async {
        let scratch = Scratch()
        scratch.maker = FakeWebAppMaker(.failure(.notAWebAddress))
        scratch.maker.result = .success(MadeWebApp(bundleID: "x", name: "X", url: URL(fileURLWithPath: "/x.app"), alreadyThere: false))
        scratch.maker.waitsForCancel = true
        let (sut, _) = makeSUT(scratch)
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.phase == .opening }

        sut.addWebApp.model.windowClosed() // the window's Cancel, or its close button
        #expect(sut.addWebApp.model.phase == .entering)
        await TestWait.until { scratch.maker.wasCancelled }
        #expect(scratch.opened.isEmpty)
        #expect(sut.status.chosenPlayerID == Players.first)

        scratch.maker.waitsForCancel = false
        scratch.maker.result = .failure(.noAnswer(host: "play.qobuz.com"))
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.problem != nil }
        #expect(sut.addWebApp.model.problem == .noAnswer(host: "play.qobuz.com"))
    }

    @MainActor
    @Test("adding the web app already chosen and learned just closes the window")
    func addWebAppAlreadyChosen() async {
        let scratch = Scratch()
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learned,
                                        installedURL: appURL)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL,
                                                            alreadyThere: true)))
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        sut.addWebApp.show()
        sut.addWebApp.model.address = "play.qobuz.com"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { !scratch.addWindow.isOpen }
    }

    @MainActor
    @Test("the learned buttons of deleted web apps are forgotten; installed ones' are kept")
    func forgetsDeletedWebApps() {
        let scratch = Scratch()
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.KEPT", name: "Qobuz", status: .learned,
                                        installedURL: appURL)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        let store = InMemoryPreferenceStore()
        store.set([webApp.bundleID: ["play": "Play"], "com.apple.Safari.WebApp.GONE-\(UUID())": ["play": "Play"]],
                  forKey: Preferences.webAppButtonsKey)
        scratch.preferences = Preferences(store: store)
        _ = makeSUT(scratch)
        let kept = store.object(forKey: Preferences.webAppButtonsKey) as? [String: Any]
        #expect(kept.map { Array($0.keys) } == [webApp.bundleID])
    }

    @MainActor
    @Test("a web app that can't be added says why, and keeps the address to try again")
    func addWebAppFails() async {
        let scratch = Scratch()
        scratch.maker = FakeWebAppMaker(.failure(.noAnswer(host: "nowhere.example")))
        let (sut, _) = makeSUT(scratch)
        sut.addWebApp.show()
        sut.addWebApp.model.address = "nowhere.example"
        sut.addWebApp.model.continueTapped()
        await TestWait.until { sut.addWebApp.model.problem != nil }
        #expect(sut.addWebApp.model.problem == .noAnswer(host: "nowhere.example"))
        #expect(sut.addWebApp.model.phase == .entering)
        #expect(sut.addWebApp.model.address == "nowhere.example")
        #expect(sut.addWebApp.model.problemText?.contains("nowhere.example") == true)
        #expect(sut.status.chosenPlayerID == Players.first)
    }

    @MainActor
    @Test("a chosen web app that's deleted is no longer chosen: no Controls row, the status line asks for a player, and the welcome window opens")
    func chosenWebAppDeleted() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.DELETED-\(UUID())", name: "Spotify",
                                        status: .learning(hasPlayed: false),
                                        installedURL: URL(fileURLWithPath: "/Users/test/Applications/Spotify.app"))
        let found = Locked<[any MusicPlayer]>([])
        found.value = [webApp]
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.value })
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        #expect(sut.status.canLearnControlsAgain)

        found.value = [] // moved to the Trash, or deleted
        scratch.changeFolder()
        await TestWait.until { sut.status.chosenPlayerID == nil }
        #expect(!sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.chosenPlayer == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(sut.status.health == .waitingForPlayer)
        #expect(scratch.chooser.isOpen)
    }

    @MainActor
    @Test("a web app chosen earlier and not learned yet is offered to learn at launch, without opening the window")
    func learningAtLaunch() {
        let scratch = Scratch()
        let webApp = scratch.offerWebApp(.learning(hasPlayed: false))
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.canLearnControlsAgain && sut.settingsModel.learning == .learning(hasPlayed: false))
        #expect(!scratch.learningWindow.isOpen)
    }
}
