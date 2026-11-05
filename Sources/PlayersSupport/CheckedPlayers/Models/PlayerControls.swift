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
    package let switches: BackupSwitches
    /// An app added before backups were kept: Check Again gives it some.
    package let needsCheckAgain: Bool
    /// A web app whose Play/Pause isn't learned yet: no backups until it is.
    package let notLearned: Bool
    package let last: LastControls

    package init(main: Control, backups: [Control], switches: BackupSwitches, needsCheckAgain: Bool = false,
                 notLearned: Bool = false, last: LastControls = LastControls()) {
        self.main = main
        self.backups = backups
        self.switches = switches
        self.needsCheckAgain = needsCheckAgain
        self.notLearned = notLearned
        self.last = last
    }

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
