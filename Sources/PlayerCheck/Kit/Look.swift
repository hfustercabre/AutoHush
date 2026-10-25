import AutoHushKit

/// The signs of whether it plays, surest first: its scripted state, what it
/// reports to Now Playing, its page's Play/Pause (while its word is current),
/// its level (as AutoHush hears it), its keep-awake assertion (as AntiDot
/// mode reads it), its menu's state (as AutoHush's MenuPlayer reads it).
/// A menu's word may change late by itself (one said Play while playing,
/// then Pause a second later, with nothing pressed), so it comes last.
package enum SignKind: CaseIterable, Sendable { case script, report, page, level, awake, menu }

/// What can be seen of whether it plays: the menu's first item, its
/// scripted state, what it reports to Now Playing, its page's Play/Pause,
/// its sound output, its level (when measured) and its keep-awake assertion.
package struct Look: Sendable {
    package var menuTitle: String?
    /// As its menu's item tells it (`menuState`): stopped while disabled.
    package var menuState: PlayerState?
    package var state: PlayerState?
    /// What it reports to Now Playing, as the log says it ("Playing", "Paused"…).
    package var reported: String?
    package var pageToggle: String?
    /// What `pageToggle`'s word says, as the page's learned button reads it
    /// (`wordSays`); nil for a word it doesn't know.
    var pageSays: PlayerState?
    /// Whether `pageToggle`'s word is current (`pageWordCurrent`); a stale
    /// one is shown, but nothing is judged by it.
    package var pageCurrent: Bool
    package var sounding: Bool
    /// Heard by its level; nil when not measured.
    package var audible: Bool?
    /// As its keep-awake assertions tell it (`awake`); nil while they don't.
    package var awake: Bool?

    package init(menuTitle: String? = nil, menuState: PlayerState? = nil, state: PlayerState? = nil, reported: String? = nil,
                 pageToggle: String? = nil, pageSays: PlayerState? = nil, pageCurrent: Bool = true, sounding: Bool,
                 audible: Bool? = nil, awake: Bool? = nil) {
        self.menuTitle = menuTitle
        self.menuState = menuState
        self.state = state
        self.reported = reported
        self.pageToggle = pageToggle
        self.pageSays = pageSays
        self.pageCurrent = pageCurrent
        self.sounding = sounding
        self.audible = audible
        self.awake = awake
    }

    /// What one sign says; nil when it says nothing (not read, or a page's
    /// stale or unknown word).
    package func says(_ kind: SignKind) -> PlayerState? {
        switch kind {
        case .script: state
        case .report: reported.flatMap(NowPlayingReports.state(reported:))
        case .page: pageCurrent ? pageSays : nil
        case .level: audible.map { $0 ? .playing : .paused }
        case .awake: awake.map { $0 ? .playing : .paused }
        case .menu: menuState
        }
    }
    /// The surest sign that says something.
    package var surest: SignKind? { SignKind.allCases.first { says($0) != nil } }
    /// Stopped, as its surest state tells it: its scripted state, else what
    /// it reports to Now Playing, else its menu's item (disabled). A track
    /// that ends leaves it so (one with a playing flag said stopped, not paused).
    package var stopped: Bool { [SignKind.script, .report, .menu].lazy.compactMap(says).first == .stopped }
}
