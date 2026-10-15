import AppKit
import CheckedPlayers
import ScriptablePlayers
import WebAppPlayers

// MARK: - What a check found, for AutoHush (--result)

/// A way's mark over the window states it was tested in (its only run when
/// there were none), and the states it failed in when it worked in some.
@MainActor func resultMark(_ key: Way) -> (mark: CheckResult.Mark, failed: [CheckResult.WindowState]) {
    if let results = stateResults[key], !results.isEmpty {
        let failed = results.filter { $0.result != .worked }.map { CheckResult.WindowState($0.state) }
        return (failed.isEmpty ? .works : failed.count == results.count ? .none : .some, failed)
    }
    guard let result = firstResults[key] else { return (.notTried, []) }
    return (result == .worked ? .works : .none, [])
}

extension CheckResult.WindowState {
    init(_ state: WindowState) {
        switch state {
        case .visible: self = .visible
        case .covered: self = .covered
        case .otherDesktop: self = .otherDesktop
        case .otherDesktopCovered: self = .otherDesktopCovered
        case .fullScreen: self = .fullScreen
        case .minimized: self = .minimized
        case .hidden: self = .hidden
        }
    }
}

/// Writes what the check found to --result's file: each way's mark (as
/// `reportWays` says it), and the setup of those that worked, those that
/// worked in every state first, the panel last (`CheckedPlayer`'s order).
@MainActor func writeResult() {
    guard let resultFile, testing else { return }
    var ways: [CheckResult.WayResult] = []
    var working: [(way: PlayerSetup.Way, everywhere: Bool, order: Int)] = []
    func add(_ kind: CheckResult.WayKind, _ found: Bool, notChecked: Bool = false, setup: () -> PlayerSetup.Way?) {
        guard found, !(notChecked && firstResults[Way(rawValue: kind.rawValue)!] == nil) else {
            ways.append(CheckResult.WayResult(kind: kind, mark: notChecked ? .notChecked : .notThere))
            return
        }
        let (mark, failed) = resultMark(Way(rawValue: kind.rawValue)!)
        let result = CheckResult.WayResult(kind: kind, mark: mark, failedStates: mark == .some ? failed : [])
        ways.append(result)
        if result.worked, let way = setup() {
            working.append((way, mark == .works, [.script: 0, .page: 1, .menu: 2, .panel: 3][kind]!))
        }
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
        .page(PageAccess(interface: PageAccess.interface(ofAppAt: appURL), switchAttribute: pageSwitch))
    }
    add(.panel, canBeNowPlaying, notChecked: unread && canBeNowPlaying) { .panel(rememberedRow: panelRowText) }
    // The panel last, whatever; then those that worked in every state.
    let ordered = working.sorted { ($0.order == 3 ? 1 : 0, $0.everywhere ? 0 : 1, $0.order) < ($1.order == 3 ? 1 : 0, $1.everywhere ? 0 : 1, $1.order) }
    let setup = ordered.isEmpty ? nil
        : PlayerSetup(bundleID: bundleID, name: appName, appURL: appURL, ways: ordered.map(\.way),
                      stateNotification: announcingNotification, needsLaunchOption: LaunchOption.needed(by: appURL) != nil)
    let result = CheckResult(ways: ways, setup: setup, pageButton: page?.toggle == nil ? nil : learned?.recipe ?? savedRecipe)
    do {
        try JSONEncoder().encode(result).write(to: resultFile, options: .atomic)
    } catch {
        log("couldn't write the result to \(resultFile.path): \(error)")
    }
}
