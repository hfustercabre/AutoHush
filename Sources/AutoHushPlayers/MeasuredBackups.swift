import AutoHushKit
import CheckedPlayers
import ScriptablePlayers
import WebAppPlayers

/// The built-in players' backups, as Player Check found them in the test VM
/// on macOS 27 (2026-11-05; the user's pick: each gets the other ways that
/// worked, Spotify's page too, learned by AutoHush itself): how each did in
/// each window state. Full screen wasn't reached for VLC's and QuickTime
/// Player's audio windows. TIDAL, signed out, plays 30-second previews, too
/// short for its check: its panel is untested. Check them again after a
/// player's major update.
extension BuiltInBackups {
    private static let everywhere = worked(in: CheckResult.WindowState.trip)
    /// Every state but full screen, which an audio window doesn't reach.
    private static let notFullScreen = worked(in: CheckResult.WindowState.trip.filter { $0 != .fullScreen })

    static let spotify = BuiltInBackups(own: .script, backups: [
        Backup(.menu(name: "Playback"), everywhere),
        Backup(.page(PageAccess(interface: .cef, switchAttribute: PageAccess.voiceOverSwitch)),
               worked(in: CheckResult.WindowState.trip.filter { $0 != .hidden }, failed: [.hidden])),
        Backup(.panel(song: .currentTrack), everywhere),
    ])

    static let appleMusic = BuiltInBackups(own: .script, backups: [
        Backup(.menu(name: "Controls"), everywhere),
        Backup(.panel(song: .currentTrack), everywhere),
    ])

    static let vlc = BuiltInBackups(own: .script, backups: [
        Backup(.menu(name: "Playback"), notFullScreen),
        Backup(.panel(song: .property("AANA")), notFullScreen),
    ])

    static let applePodcasts = BuiltInBackups(own: .menu, backups: [Backup(.panel(song: nil), everywhere)])

    static let tidal = BuiltInBackups(own: .menu, backups: [Backup(.panel(song: nil), [:])])

    static let quickTime = BuiltInBackups(own: .script, backups: [Backup(.panel(song: nil), notFullScreen)])
}
