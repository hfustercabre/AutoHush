import AppKit
import AutoHushKit

// StatusMenuController: what the menu's controls do.
extension StatusMenuController {
    /// What the menu's controls ask for. Switches and the players' search
    /// act at once and keep the menu open; what opens a window or an
    /// alert closes it first, as a menu's rows do; choosing a player keeps
    /// it open (the user, 2026-10-18).
    func perform(_ command: StatusMenuCommand) {
        switch command {
        case .toggleAutoPause:
            settings.toggleAutoPause()
        case .setIgnored(let source, let ignored):
            settings.setIgnored(source, ignored)
        case .choosePlayer(let id):
            // In place (the user, 2026-10-18): the side window closes, and the
            // card, its checks and the settings follow the new player. A window
            // the choice opens (Add a Web App, learning) or an alert closes the
            // menu as it comes forward (`watchOtherWindows`).
            closeSide()
            actions?.choosePlayer(id)
        case .searchPlayers(let search):
            guard model.isChoosingPlayer else { return } // a closing field handing its text back
            model.playerSearch = search
        case .typeInSearch:
            searchTakesKeyboard()
        case .moveHighlight(let step):
            model.sideKeyboard.move(step)
        case .chooseHighlighted:
            // The first player the search left, only while something is typed
            // (the full check, 2026-10-18: with none, Return changed the player).
            guard !model.sideKeyboard.press(), !model.playerSearch.isEmpty,
                  let id = model.players.choosable.first?.id else { return }
            perform(.choosePlayer(id))
        case .openSide(let part):
            guard model.openSide != part else { return }
            open(part)
        case .hoverSideRow(let part, let inside):
            hoverSideRow(part, inside)
        case .pointerEntered(let section):
            pointerEntered(section)
        case .retry:
            model.announcesRetryOutcome = true
            session.retry() // the card shows how it goes
        case .retryResume:
            model.announcesResumeOutcome = true
            session.retryResume() // the card shows how it goes
        case .updates where status.updateOffer == nil:
            // The menu stays open, its button saying "Checking…", until the
            // result: its alert closes the menu first (`close`).
            guard !model.isCheckingForUpdates else { return }
            model.isCheckingForUpdates = true
            Task { [weak self] in
                await self?.updates.checkNow()
                self?.model.isCheckingForUpdates = false
            }
        default:
            guard command.closesMenuFirst else { return }
            close()
            // Once the menu has closed, as for a menu's rows.
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.run(command) }
            }
        }
    }

    private func run(_ command: StatusMenuCommand) {
        switch command {
        case .snooze(let snooze):        settings.snooze(snooze)
        case .removeAddedApp(let id):    actions?.removeAddedApp(id)
        case .addApp:                    actions?.openAddApp()
        case .addWebApp:                 actions?.openAddWebApp()
        case .ignoreAnotherApp:          IgnoreAppsPicker.run(player: status.chosenPlayer) { settings.setIgnored($0, true) }
        case .resolveWarning(let need):  actions?.requestPermission(need)
        case .reopenAutoHush:            actions?.reopenAutoHush()
        // Through Settings' model, whose guard keeps AntiDot mode off for a
        // player only its sound tells about (U18, the full check, 2026-10-19).
        case .useAntiDotMode:            settingsModel?.useAntiDotMode()
        case .showUpdate:                updates.presentAvailableUpdate()
        case .openSettings:              actions?.openSettings(page: nil)
        case .showDiagnostics:           actions?.openSettings(page: .diagnostics)
        case .updates:                   updates.presentAvailableUpdate() // checking keeps the menu open: `perform`
        case .showAbout:                 actions?.openSettings(page: .about)
        case .showControlError:          actions?.showControlError()
        case .learnControls:             actions?.learnControlsAgain()
        case .reopenPlayer:              actions?.reopenPlayer()
        case .unmutePlayer:              actions?.unmutePlayer()
        case .quit:                      actions?.quit()
        default:                         break // they act in perform(_:) (`closesMenuFirst`)
        }
    }
}
