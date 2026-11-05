import AutoHushKit
import CheckedPlayers

/// What Settings greys out beyond a switch's own rules
/// (`SettingsSwitch.isUnavailable(_:)`): the fade lengths, the fade-in, and
/// Level the volume's limits and note.
extension SettingsModel {
    /// The fade lengths greyed out, in Settings: the fades are off, or the
    /// player can't fade.
    var fadeLengthsUnavailable: Bool {
        !timings.fadesEnabled || !playerCanFade
    }

    /// The fade-in greyed out on its own, in Settings: nothing
    /// resumes, while the fades otherwise apply.
    var fadeInUnused: Bool {
        !timings.resumesPlayback && timings.fadesEnabled && playerCanFade
    }

    /// Level the volume can't be changed (its switch's rule,
    /// `SettingsSwitch.isUnavailable(_:)`): AntiDot mode, or Resume playback off.
    var levelingUnavailable: Bool { SettingsSwitch.levelsMusic.isUnavailable(self) }

    /// Level the volume's limits greyed out, in Settings: it's
    /// off, or can't be on.
    var levelingLimitsUnavailable: Bool {
        !timings.levelsMusic || levelingUnavailable
    }

    /// Why Level the volume can't be changed, in a few words without a
    /// period: Behavior's and Fine-Tuning's Volume note; `nil` while it can.
    /// The other switches say why in a note of their own (U6, 2026-10-27).
    var levelingUnavailableNote: String? {
        guard levelingUnavailable else { return nil }
        return isAntiDotMode ? AntiDotText.featureOff : SettingsSwitch.resumeOffNote
    }

    /// The chosen player's own control permission, missing while its
    /// backup controls stand in for it: macOS doesn't allow its own way,
    /// but AutoHush still controls it by the others (`passesOverOwnWay`).
    /// The menu warns with it, and Settings' note says so (the user,
    /// 2026-11-05). `nil` while it can't be controlled at all (the card and
    /// the note ask then), or while another main control is chosen (its own
    /// way is only a backup then).
    var backupsStandIn: Permission? {
        guard state.missingPermission == nil, let control = permissions.control,
              permissions.controlMissing(for: chosenPlayerID), permissions.controlAccess != .playerNotRunning,
              let controls = chosenControls, controls.backupsInUse, !controls.mainChanged else { return nil }
        return control
    }
}
