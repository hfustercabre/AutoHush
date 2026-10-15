import AppKit
import CheckedPlayers
import PlayerCheckKit
import ScriptablePlayers
import WebAppPlayers

// MARK: - What a check found, for AutoHush (--result)

/// A way's mark over the window states it was tested in (its only run when
/// there were none), and the states it failed in when it worked in some.
@MainActor func resultMark(_ key: Way) -> (mark: CheckResult.Mark, failed: [CheckResult.WindowState]) {
    if let results = stateResults[key], !results.isEmpty {
        let failed = results.filter { $0.result != .worked }.map(\.state)
        return (failed.isEmpty ? .works : failed.count == results.count ? .none : .some, failed)
    }
    guard let result = firstResults[key] else { return (.notTried, []) }
    return (result == .worked ? .works : .none, [])
}

/// Writes what the check found to --result's file: each way's mark (as
/// `reportWays` says it), and the setup of those that worked and AutoHush
/// can run by itself (`ResultWays`), in `CheckedPlayer`'s order. Its menu and
/// its page were found as AutoHush finds them, so AutoHush can press what
/// worked; AppleScript that only toggles, with no state, needs another sign.
@MainActor func writeResult() {
    guard let resultFile, testing else { return }
    var ways: [CheckResult.WayResult] = []
    var working: [ResultWays.Working] = []
    func add(_ kind: CheckResult.WayKind, _ found: Bool, notChecked: Bool = false, setup: () -> PlayerSetup.Way?) {
        guard found, !(notChecked && firstResults[Way(rawValue: kind.rawValue)!] == nil) else {
            ways.append(CheckResult.WayResult(kind: kind, mark: notChecked ? .notChecked : .notThere))
            return
        }
        let (mark, failed) = resultMark(Way(rawValue: kind.rawValue)!)
        let result = CheckResult.WayResult(kind: kind, mark: mark, failedStates: mark == .some ? failed : [])
        ways.append(result)
        if result.worked, let way = setup() { working.append(ResultWays.Working(way: way, kind: kind, everywhere: mark == .works)) }
    }
    let unread = running == nil || !AXIsProcessTrusted()
    // Not allowed to script it (--partial): its AppleScript wasn't tried.
    add(.script, scriptControls() != nil, notChecked: automationAnswer == .denied || (partial && automationAnswer != .allowed)) {
        scripting.flatMap(ScriptSetup.init(dictionary:)).map { .script($0) }
    }
    add(.menu, menu != nil, notChecked: unread) { menu.map { .menu(menuName: $0.title) } }
    // No page at all is no page button; not read for another reason is unchecked.
    let noPage = ["no page in its windows", "no switch was taken"].contains(pageNotChecked ?? "")
    add(.page, page?.toggle != nil, notChecked: unread || (pageNotChecked != nil && !noPage)) {
        .page(PageAccess(interface: pageAccess.interface, switchAttribute: pageSwitch))
    }
    add(.panel, canBeNowPlaying, notChecked: unread && canBeNowPlaying) { .panel(rememberedRow: panelRowText) }
    // Never found in the menu bar: Now Playing is hidden there, which the user can change.
    if !panelItemSeen, panelItemMissing, let index = ways.firstIndex(where: { $0.kind == .panel }), ways[index].mark == .none {
        ways[index] = CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)
    }
    // A toggle with no state and nothing else to tell AutoHush when to send it: not kept.
    if let index = working.firstIndex(where: { $0.kind == .script }), case .script(let script) = working[index].way,
       !ResultWays.canRun(script, besides: working.map(\.way), reportsReadable: canBeNowPlaying && isAdministrator) {
        working.remove(at: index)
        if let marked = ways.firstIndex(where: { $0.kind == .script }) { ways[marked] = CheckResult.WayResult(kind: .script, mark: .notTried) }
        log("  AppleScript's toggle isn't kept: it has no state, and nothing else tells AutoHush when to send it")
    }
    let ordered = ResultWays.ordered(working)
    let setup = ordered.isEmpty ? nil
        : PlayerSetup(bundleID: bundleID, name: appName, appURL: appURL, ways: ordered,
                      stateNotification: announcingNotification, needsLaunchOption: LaunchOption.needed(by: appURL) != nil)
    let result = CheckResult(ways: ways, setup: setup, pageButton: page?.toggle == nil ? nil : learned?.recipe ?? savedRecipe)
    do {
        try JSONEncoder().encode(result).write(to: resultFile, options: .atomic)
    } catch {
        log("couldn't write the result to \(resultFile.path): \(error)")
    }
}
