import SwiftUI
import AutoHushKit

/// The switches of Settings → Behavior, as Diagnostics names them too: the
/// same words, and the rules for when one can't be changed.
enum SettingsSwitch {
    case antiDot, pausesOnDisconnect, resumesPlayback, fades, levelsMusic, pausesForMicrophone, staysPausedAfterCalls

    /// Its name: the switch's and Diagnostics' row's.
    var name: String {
        switch self {
        case .antiDot:
            String(localized: "AntiDot mode", comment: "Settings → Behavior, and Diagnostics: the switch for AntiDot mode, which hides the purple recording indicator")
        case .pausesOnDisconnect:
            String(localized: "Pause on disconnect", comment: "Settings → Behavior (under “Pausing”), and Diagnostics: the switch that pauses your player at once when the headphones (or another output) it plays through are unplugged or go out of range")
        case .resumesPlayback:
            String(localized: "Resume playback", comment: "Settings → Behavior (under “Resuming”), and Diagnostics: the switch that resumes your player once the other apps go quiet; off, AutoHush only pauses it")
        case .fades:
            String(localized: "Fade playback", comment: "Settings → Behavior: the switch that turns the fades on or off")
        case .levelsMusic:
            String(localized: "Level the volume", comment: "Settings → Behavior, and Diagnostics: the switch that lowers the Mac’s volume as your player resumes after quieter apps, to match them")
        case .pausesForMicrophone:
            String(localized: "Pause for the microphone", comment: "Settings → Behavior, and Diagnostics: the switch that pauses your player as soon as an app turns on the microphone")
        case .staysPausedAfterCalls:
            String(localized: "Stay paused after calls", comment: "Settings → Behavior, and Diagnostics: the switch that keeps your player paused after a call")
        }
    }

    /// `name` as a view's text.
    var title: Text { Text(verbatim: name) }

    /// What it does, under it in Settings.
    var subtitle: Text {
        switch self {
        case .antiDot:
            Text("Hides the purple recording indicator. Detection is less precise.",
                 comment: "Settings, under AntiDot mode")
        case .pausesOnDisconnect:
            Text("Headphones and other outputs: your player stays paused instead of moving to the speakers. Some players already do this themselves.",
                 comment: "Settings → Behavior, under “Pause on disconnect”: when headphones or another output (Bluetooth or USB speakers) are unplugged or go out of range; AutoHush doesn’t resume it. Some media players already pause on their own when that happens")
        case .resumesPlayback:
            Text("Once other apps go quiet. Turned off, your player stays paused until you play it.",
                 comment: "Settings → Behavior, under “Resume playback”: when it resumes your player; turned off, AutoHush only pauses it")
        case .fades:
            Text("Out before pausing, and back in when resuming.",
                 comment: "Settings → Behavior, under “Fade playback”")
        case .levelsMusic:
            Text("After quieter apps, your player resumes with the Mac’s volume lowered to match. Calls don’t count.",
                 comment: "Settings → Behavior, under “Level the volume”; a call is an app using the microphone")
        case .pausesForMicrophone:
            Text("An app turning on the microphone pauses your player, even before it plays.",
                 comment: "Settings → Behavior, under “Pause for the microphone”: a call that starts silent pauses your player too")
        case .staysPausedAfterCalls:
            Text("Your player doesn’t resume after a call that came while it was paused.",
                 comment: "Settings → Behavior, under “Stay paused after calls”; a call is an app using the microphone")
        }
    }

    /// Off and dimmed: AntiDot mode with a player only its sound tells
    /// about, the fades with a player AutoHush can't fade, leveling in
    /// AntiDot mode (which measures no sound); dimmed, leveling and
    /// staying paused after calls while Resume playback is off (nothing
    /// resumes).
    @MainActor func isUnavailable(_ model: SettingsModel) -> Bool {
        switch self {
        case .antiDot: !model.isAntiDotMode && model.antiDotUnavailableFor != nil
        case .fades: !model.playerCanFade
        case .levelsMusic: model.isAntiDotMode || !model.timings.resumesPlayback
        case .staysPausedAfterCalls: !model.timings.resumesPlayback
        case .pausesOnDisconnect, .resumesPlayback, .pausesForMicrophone: false
        }
    }

    /// What it shows: off while it can't be changed, whatever is saved (the
    /// saved value comes back once it can). Stay paused after calls keeps
    /// showing the user's choice (the user, 2026-10-21): with Resume
    /// playback off, the player stays paused after calls anyway.
    @MainActor func isOn(_ model: SettingsModel) -> Bool {
        guard !isUnavailable(model) || self == .staysPausedAfterCalls else { return false }
        return switch self {
        case .antiDot: model.isAntiDotMode
        case .pausesOnDisconnect: model.timings.pausesOnOutputDisconnect
        case .resumesPlayback: model.timings.resumesPlayback
        case .fades: model.timings.fadesEnabled
        case .levelsMusic: model.timings.levelsMusic
        case .pausesForMicrophone: model.timings.pausesForMicrophone
        case .staysPausedAfterCalls: model.timings.staysPausedAfterCalls
        }
    }

    @MainActor func set(_ isOn: Bool, in model: SettingsModel) {
        var timings = model.timings
        switch self {
        case .antiDot: return model.setAntiDotMode(isOn)
        case .pausesOnDisconnect: timings.pausesOnOutputDisconnect = isOn
        case .resumesPlayback: timings.resumesPlayback = isOn
        case .fades: timings.fadesEnabled = isOn
        case .levelsMusic: timings.levelsMusic = isOn
        case .pausesForMicrophone: timings.pausesForMicrophone = isOn
        case .staysPausedAfterCalls: timings.staysPausedAfterCalls = isOn
        }
        model.setTimings(timings)
    }

    /// Under what only matters when resuming, dimmed while Resume playback
    /// is off: a note in Settings.
    static var resumeOffNote: String {
        String(localized: "Resume playback is off",
               comment: "Under settings that only matter when your player resumes (Resume playback after, Fade in when resuming, Level the volume, Stay paused after calls), dimmed while the Resume playback switch (Settings → Behavior) is off: Settings → Behavior and Fine-Tuning")
    }

    /// Under what a switch turns on, dimmed while it's off, as
    /// `resumeOffNote` (the user's pick, the workflow audit, 2026-10-22).
    static var antiDotOffNote: String {
        String(localized: "AntiDot mode is off",
               comment: "Settings → Fine-Tuning, Detection: under AntiDot mode's ways of detecting, dimmed while the AntiDot mode switch (Settings → Behavior) is off")
    }

    static var fadesOffNote: String {
        String(localized: "Fade playback is off",
               comment: "Settings → Fine-Tuning, under the fades' lengths, dimmed while the Fade playback switch (Settings → Behavior) is off")
    }

    static var levelingOffNote: String {
        String(localized: "Level the volume is off",
               comment: "Settings → Fine-Tuning, under the volume's limits, dimmed while the Level the volume switch (Settings → Behavior) is off")
    }

    /// Under the dimmed Fade playback, for a player AutoHush can't fade;
    /// Fine-Tuning's Fade Lengths too.
    static func cantFadeNote(_ player: String) -> String {
        String(localized: "\(player) pauses and resumes without fading: AutoHush can’t change its volume.",
               comment: "Settings → Behavior and Fine-Tuning, under the dimmed fade settings; %@ is the media player")
    }

    static var updateChecksOffNote: String {
        String(localized: "Automatic checks are off",
               comment: "Settings → About, under what happens when an update is found, dimmed while the switch “Check for updates automatically” is off")
    }
}
