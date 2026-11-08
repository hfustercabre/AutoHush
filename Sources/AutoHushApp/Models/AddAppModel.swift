import Foundation
import AutoHushKit
import CheckedPlayers
import PlayerCheckKit

/// How adding an app goes (Add an App…), step by step, for its window
/// (W2): choose the app, allow what the check needs (only what that app
/// needs, all at once), reopen it with its launch option if it needs one,
/// play something in it, the check (after a warning, W6), then what worked
/// and Use.
@MainActor
@Observable
final class AddAppModel {
    enum Stage: Equatable {
        case choosing
        /// The chosen app opening in the background, or being looked at.
        case opening
        case allowing
        /// Asks before reopening it with its launch option.
        case reopenAsked
        case reopening
        /// The chosen app opening again after it quit while it was waited
        /// for: the play step is busy, the steps before keep their ticks.
        case openingAgain
        case waitingToPlay(since: Date)
        case playTimedOut
        /// It plays: the check can start (its Continue… shows the warning).
        case ready
        case checking
        case stopped
        case failed
        case done(CheckResult)
    }

    enum Step: CaseIterable {
        case choose, allow, reopen, play, check, use
    }

    enum ReopenOutcome: String, Codable, Equatable {
        case reopened, skipped
    }

    /// How long the user has to start the app playing.
    static let playWait: TimeInterval = 120

    // Where adding the app stands. Its parts by topic (AddAppModel+Steps,
    // +Permissions, +Check and +Use) set it; the windows read it, and set
    // only the search and the selection (AddAppModelGuardTests checks it).
    var stage = Stage.choosing
    var apps: [CheckableApp] = []
    var isLoadingApps = false
    var search = ""
    /// Another selection drops Other App…'s warning, which was about the
    /// app picked on the disk (A1, the user, 2026-10-19).
    var selectedID: String? {
        didSet { if selectedID != oldValue { otherAppProblem = nil } }
    }
    var chosen: CheckableApp?
    var traits: CheckedAppTraits?
    var permissions = CheckPermissions() {
        didSet { readMacMuting() } // as the steps that say how the check mutes show
    }
    /// It ran without the launch option it needs: the Reopen step shows.
    var needsReopen = false
    var reopenOutcome: ReopenOutcome?
    /// The last reopen or open didn't go.
    var reopenFailed = false
    var openFailed = false
    /// Why the app last picked on the disk can't be checked.
    var otherAppProblem: OtherAppProblem?
    /// Counts each note shown (`showOtherAppProblem`), so VoiceOver hears it
    /// again when the same one comes twice (the 1.3.1 review's WA-2).
    var otherAppProblemShown = 0
    /// The app picked on the disk since the window opened or started over
    /// (Other App…, or AutoHush reopened for it), which the apps read aren't
    /// sure to list: kept in the list while it's there (the 2026-11-08 diff
    /// review's finding 1); forgotten at the next opening (finding 2).
    var pickedOnDisk: CheckableApp?
    /// The check found Accessibility missing after all (`CheckExitStatus.permissionMissing`).
    var permissionMissingInCheck = false
    /// The check found Accessibility missing while AutoHush still reads it
    /// allowed: macOS gives a running app such a change only when it says
    /// so, which it doesn't always (`tccutil reset`; measured in the VM,
    /// 2026-10-22), so AutoHush sees it once it reopens. Until then,
    /// nothing goes on by itself; Reopen AutoHush is offered.
    var accessibilityNeedsReopen = false
    var progress = CheckProgress()
    /// The chosen app quit while it was waited for, or during the check.
    var appQuit = false
    /// It quit and isn't where it was chosen (moved or deleted): another
    /// app is chosen instead (Change…), as Open can't find it.
    var appNotFound = false
    /// Why the last check couldn't finish, as far as AutoHush can tell.
    var failureReason: PlayerCheckEnd.Reason?
    /// Audio Recording was allowed in System Settings (here or elsewhere in
    /// AutoHush): macOS applies it once AutoHush reopens.
    var audioAwaitsReopen: Bool { permissions.audio == .needsReopen }
    /// A check that was stopped and still puts things back: the next one
    /// waits for it.
    var isEndingLastCheck = false
    /// Stop was pressed (the window's, Escape or the panel's): the check
    /// puts things back before it ends, both say so.
    var isStopping = false
    /// The way the user chose among those that worked (`chosenWay`).
    var pickedWay: CheckResult.WayKind?
    /// The backup switches the user set in the last step (`backupSwitches`).
    var pickedSwitches: BackupSwitches?
    /// What Check Again beside Use left until the new check ends, the app
    /// changes or Back to Result: one value, so none is left half set.
    struct CheckAgainState {
        /// The result it left beside Use: Back to Result brings it back
        /// until the new check starts (`canGoBackToResult`).
        let resultBefore: KeptCheck?
        /// Its windows were closed: the play step waits for a window the
        /// check can reach too (`waitForPlaying`; B2, 2026-10-29).
        let waitsForWindow: Bool
        /// While it waits for one: none is open yet.
        var windowMissing = false
    }
    var checkAgainState: CheckAgainState?
    var resultBeforeCheckAgain: KeptCheck? { checkAgainState?.resultBefore }
    var waitsForWindow: Bool { checkAgainState?.waitsForWindow ?? false }
    var windowMissing: Bool { checkAgainState?.windowMissing ?? false }
    /// While it's ready to be checked, the chosen app has no window the
    /// check can reach, as last looked at (every 2 s; a menu bar player
    /// playing on): the check moves nothing then and leaves the mouse and
    /// keyboard free, as the warning before it says (W2 of 1.2.2, the
    /// release review, 2026-11-07).
    var appWindowsClosed = false
    /// How many times AntiDot mode was turned off from here.
    var antiDotChanges = 0
    /// Whether the Mac's output could be muted, as last read: as the
    /// permissions are read, and as the warning before the check opens. The
    /// steps' notes, the warning and the check's start all go by it, so
    /// they agree, and Core Audio isn't asked at every drawing. The check's
    /// start mutes the output in use then (`OutputMute.mute`).
    var macCanMute = false

    /// The apps on the Mac, and the check's helper (`nil`: missing from
    /// the app, so nothing can be checked).
    @ObservationIgnored let reader: any AppReading
    @ObservationIgnored let helper: any CheckHelping?
    /// What it needs from the rest of AutoHush, and what it shows through
    /// the feature that owns it (weak: they own it).
    @ObservationIgnored private(set) weak var host: any AddAppHost?
    @ObservationIgnored private(set) weak var presenter: any AddAppPresenting?
    /// Where a finished check's result is kept until it's used or replaced
    /// (a reopen of AutoHush, or the window closed, doesn't lose it).
    @ObservationIgnored let keptChecks: KeptCheckStore
    @ObservationIgnored let now: @MainActor () -> Date
    @ObservationIgnored let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored var run: any CheckRunning?
    /// A stopped check still putting things back.
    @ObservationIgnored var endingRun: any CheckRunning?
    /// Watching the permissions, or waiting for the app to play.
    @ObservationIgnored var work: Task<Void, Never>?
    /// The window is open: closed, nothing more starts (a warning's Start
    /// after the window closed, say).
    @ObservationIgnored var windowIsOpen = false

    init(reader: any AppReading, helper: any CheckHelping?, host: any AddAppHost?, presenter: any AddAppPresenting,
         keptChecks: KeptCheckStore = KeptCheckStore(), now: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.reader = reader
        self.helper = helper
        self.host = host
        self.presenter = presenter
        self.keptChecks = keptChecks
        self.now = now
        self.sleep = sleep
    }

    /// The check's helper is in the app: without it, nothing can be checked.
    var hasHelper: Bool { helper != nil }

    // MARK: - What the window shows

    /// The steps shown: Reopen only for an app that needs it.
    var steps: [Step] { Step.allCases.filter { $0 != .reopen || needsReopen } }

    /// Its number among the steps shown.
    func number(of step: Step) -> Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    /// Where `step` stands; the one AutoHush is doing now is `current`
    /// (`isBusy`).
    func state(of step: Step) -> StepState {
        let order = Step.allCases
        let at = order.firstIndex(of: currentStep)!
        let index = order.firstIndex(of: step)!
        if index < at { return .done }
        if index > at { return .todo }
        switch stage {
        case .playTimedOut, .stopped, .failed: return .failed
        case .done: return choosableWays.isEmpty ? .failed : .current
        default: return .current
        }
    }

    /// AutoHush is doing `step` now: opening the app, reopening it, or the
    /// check under way (a spinner instead of its number).
    func isBusy(_ step: Step) -> Bool {
        guard step == currentStep else { return false }
        switch stage {
        case .opening, .reopening, .openingAgain, .checking: return true
        default: return false
        }
    }

    /// The step the stage is in.
    var currentStep: Step {
        switch stage {
        case .choosing, .opening: .choose
        case .allowing: .allow
        case .reopenAsked, .reopening: .reopen
        case .openingAgain, .waitingToPlay, .playTimedOut: .play
        case .ready, .checking, .stopped, .failed: .check
        case .done: .use
        }
    }

    /// The apps matching the search: those in Now Playing first.
    var shownApps: (inNowPlaying: [CheckableApp], others: [CheckableApp]) {
        let search = search.trimmingCharacters(in: .whitespaces)
        let matching = search.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(search) }
        return (matching.filter { $0.nowPlaying != nil }, matching.filter { $0.nowPlaying == nil })
    }

    /// The apps shown, in the list's order.
    var shownAppsInOrder: [CheckableApp] { shownApps.inNowPlaying + shownApps.others }

    /// ↑ or ↓ in Choose an App's search: the app before or after the
    /// selected one among those shown, from none the first (or the last);
    /// at an end it stays. The app it selected, `nil` when the selection
    /// stayed: VoiceOver's cursor stays in the search, so the window says
    /// which (N10, the a11y audit, 2026-11-06).
    @discardableResult func moveSelection(_ step: Int) -> CheckableApp? {
        let shown = shownAppsInOrder
        guard !shown.isEmpty else { return nil }
        let index = shown.firstIndex { $0.id == selectedID }.map { $0 + step } ?? (step > 0 ? 0 : shown.count - 1)
        let app = shown[min(max(index, 0), shown.count - 1)]
        guard app.id != selectedID else { return nil }
        selectedID = app.id
        return app
    }

    var canContinueWithApp: Bool { stage == .choosing && apps.contains { $0.id == selectedID } }

    /// Another app can be chosen instead: one is, and nothing is under way.
    var canChangeApp: Bool {
        switch stage {
        case .choosing, .opening, .reopening, .openingAgain, .checking: false
        default: true
        }
    }

    var result: CheckResult? {
        if case .done(let result) = stage { result } else { nil }
    }

    /// AntiDot mode is on: nothing listens to the app, and it can't be muted.
    var antiDot: Bool {
        _ = antiDotChanges // read, so the window follows `turnOffAntiDot`
        return host?.isAntiDot ?? true
    }
}
