import os
import AutoHushKit

/// What controls a player, for Settings, its Details sheet and Diagnostics
/// (the user, 2026-11-05): its main control, its backup controls (the
/// other ways that worked in its check, or were measured for a built-in
/// player, then the Play/Pause key and the Now Playing panel), their
/// switches, and which paused and played it last.
package struct PlayerControls: Sendable, Equatable {
    /// One way to pause and play it.
    package struct Control: Sendable, Equatable {
        package let kind: WayOrder.Kind
        /// How its check found it; `nil` for the Play/Pause key, which no
        /// check tests.
        package let found: CheckResult.WayResult?

        package init(kind: WayOrder.Kind, result: CheckResult.WayResult?) {
            self.kind = kind
            found = result
        }
    }

    package let main: Control
    package let backups: [Control]
    /// The controls that can be its main one (`WayOrder.canBeMain`): its own
    /// (recommended) first, then the others that worked, in their order;
    /// never the Play/Pause key. Just its own: nothing to choose.
    package let choices: [Control]
    /// Those that will be choosable once learned (Spotify's page, learned
    /// the first time AutoHush pauses it another way), shown dimmed
    /// among them (the user, 2026-11-05).
    package let notYetChoices: [Control]
    /// The choices and those not yet choosable, in their order, as the
    /// Main control pop-up lists them.
    package let listedChoices: [Control]
    /// Its own main control: the check's choice at Use, or a built-in
    /// player's own; the one Restore Defaults goes back to.
    package let recommended: WayOrder.Kind
    package let switches: BackupSwitches
    /// An app added before backups were kept: Check Again gives it some.
    package let needsCheckAgain: Bool
    /// A web app whose Play/Pause isn't learned yet: no backups until it is.
    package let notLearned: Bool
    package let last: LastControls

    package init(main: Control, backups: [Control], switches: BackupSwitches, needsCheckAgain: Bool = false,
                 notLearned: Bool = false, last: LastControls = LastControls(), choices: [Control]? = nil,
                 recommended: WayOrder.Kind? = nil, notYetChoices: [Control] = [], listedChoices: [Control]? = nil) {
        self.main = main
        self.backups = backups
        self.choices = choices ?? [main]
        self.notYetChoices = notYetChoices
        self.listedChoices = listedChoices ?? choices ?? [main]
        self.recommended = recommended ?? main.kind
        self.switches = switches
        self.needsCheckAgain = needsCheckAgain
        self.notLearned = notLearned
        self.last = last
    }

    /// Its controls with `chosen` as the main one, the others in their order
    /// (its own first, where the chosen one was): `all` its own first, as
    /// they're pressed; `chosen` `nil`, or not among `all`, keeps its own.
    /// `notYet`: one that will be choosable once learned (listed dimmed).
    package init(all: [Control], chosen: WayOrder.Kind?, choosable: (Control, Int) -> Bool, switches: BackupSwitches,
                 needsCheckAgain: Bool = false, notLearned: Bool = false, last: LastControls = LastControls(),
                 notYet: (Control, Int) -> Bool = { _, _ in false }) {
        let mainAt = chosen.flatMap { kind in all.firstIndex { $0.kind == kind } } ?? 0
        var backups = all
        let main = backups.remove(at: mainAt)
        let choices = all.enumerated().filter { choosable($1, $0) }.map(\.element)
        let notYetChoices = all.enumerated().filter { !choosable($1, $0) && notYet($1, $0) }.map(\.element)
        self.init(main: main, backups: backups, switches: switches, needsCheckAgain: needsCheckAgain, notLearned: notLearned,
                  last: last, choices: choices, recommended: all[0].kind, notYetChoices: notYetChoices,
                  listedChoices: all.filter { control in choices.contains(control) || notYetChoices.contains(control) })
    }

    /// Another than its own is its main control now.
    package var mainChanged: Bool { main.kind != recommended }

    /// The Now Playing panel is one of its controls, its main one too (its
    /// own switch shows and decides; the user, 2026-11-05).
    package var hasPanel: Bool { main.kind == .panel || backups.contains { $0.kind == .panel } }

    /// Its backups are pressed now.
    package var backupsInUse: Bool { switches.usesBackups && !needsCheckAgain && !notLearned && !backups.isEmpty }
}

/// Which control paused and played the player last, since AutoHush started.
package struct LastControls: Sendable, Equatable {
    package var paused: WayOrder.Kind?
    package var played: WayOrder.Kind?

    package init(paused: WayOrder.Kind? = nil, played: WayOrder.Kind? = nil) {
        self.paused = paused
        self.played = played
    }

    mutating func note(_ kind: WayOrder.Kind, for target: PlayerState) {
        if target == .playing { played = kind } else { paused = kind }
    }
}

/// A player that says what controls it (`PlayerControls`).
package protocol ControlsReporting: Sendable {
    var controls: PlayerControls { get }
}
