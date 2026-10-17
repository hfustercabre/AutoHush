import AppKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

// MARK: - What a check found, for AutoHush (--result)

/// Writes what the check found to --result's file (`CheckFindings`): each
/// way's mark (as `reportWays` says it), and the setup of those that worked
/// and AutoHush can run by itself. Its menu and its page were found as
/// AutoHush finds them, so AutoHush can press what worked.
@MainActor func writeResult() {
    guard let resultFile, testing else { return }
    func found(_ kind: CheckResult.WayKind, _ isThere: Bool, notChecked: CheckResult.Mark?, setup: PlayerSetup.Way?) -> CheckFindings.Way {
        let way = Way(rawValue: kind.rawValue)
        return CheckFindings.Way(isThere: isThere, notChecked: notChecked,
                                 trials: way.map { (stateResults[$0] ?? []).map { ($0.state, $0.result) } } ?? [],
                                 first: way.flatMap { firstResults[$0] }, setup: isThere ? setup : nil)
    }
    let unread: CheckResult.Mark? = running == nil ? .notChecked : !AXIsProcessTrusted() ? .noAccessibility : nil
    // Not allowed to script it (--partial): its AppleScript wasn't tried.
    // Not checked for Automation only when its dictionary has commands to try.
    let scriptable = scriptControls() != nil
    let noAutomation = automationAnswer == .denied || (partial && automationAnswer != .allowed)
    // No page at all is no page button; not read for another reason is unchecked.
    let noPage = ["no page in its windows", "no switch was taken"].contains(pageNotChecked ?? "")
    let pageUnread: CheckResult.Mark? = pageNotChecked == nil || noPage ? nil
        : pageNotChecked == "no Accessibility permission" ? .noAccessibility : .notChecked
    var findings = CheckFindings(bundleID: bundleID, appName: appName, appURL: appURL, ways: [
        .script: found(.script, scriptable, notChecked: scriptable && noAutomation ? .noAutomation : nil,
                       setup: scripting.flatMap(ScriptSetup.init(dictionary:)).map { .script($0) }),
        .menu: found(.menu, menu != nil, notChecked: unread, setup: menu.map { .menu(menuName: $0.title) }),
        .page: found(.page, page?.toggle != nil, notChecked: unread ?? pageUnread,
                     setup: .page(PageAccess(interface: pageAccess.interface, switchAttribute: pageSwitch))),
        .panel: found(.panel, canBeNowPlaying, notChecked: canBeNowPlaying ? unread : nil, setup: .panel(rememberedRow: panelRowText)),
    ])
    findings.nowPlayingHidden = !panelItemSeen && panelItemMissing
    findings.reportsReadable = canBeNowPlaying && isAdministrator
    findings.stateNotification = announcingNotification
    findings.needsLaunchOption = LaunchOption.needed(by: appURL) != nil
    findings.panelRowIsStale = panelRowStale
    findings.pageButton = page?.toggle == nil ? nil : learned?.recipe ?? savedRecipe
    let (result, toggleLeftOut) = findings.result()
    if toggleLeftOut { log("  AppleScript’s toggle isn’t kept: it has no state, and nothing else tells AutoHush when to send it") }
    do {
        try JSONEncoder().encode(result).write(to: resultFile, options: .atomic)
    } catch {
        log("couldn’t write the result to \(resultFile.path): \(error)")
    }
}
