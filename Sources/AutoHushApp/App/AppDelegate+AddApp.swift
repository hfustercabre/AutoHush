import AppKit
import AutoHushKit
import CheckedPlayers

/// AppDelegate as Add an App's host: what the feature (`AddAppFeature`)
/// needs from the rest of AutoHush.
extension AppDelegate: AddAppHost {
    var supportedApps: [PlayerOption] { status.playerOptions.filter { $0.kind == .app } }

    var isAntiDot: Bool { userSettings.state.detection.isAntiDot }

    func turnOffAntiDot() {
        userSettings.setDetectionMethod(.audioLevels)
    }

    /// What the check of `app` needs, as it stands now, read by the rules
    /// the chosen player's permissions are (`PermissionCenter`): Automation
    /// when it's scripted. Audio Recording is read in AntiDot mode too,
    /// where the check doesn't use it: the window goes by the mode, which
    /// its last step can turn off.
    func checkPermissions(_ app: CheckableApp, scriptable: Bool) async -> CheckPermissions {
        let state = await permissionCenter.state(
            app: app.bundleID, control: scriptable ? CheckPermission.automation.permission(app: app.name) : nil,
            detectionMethod: .audioLevels, detection: status.detection, awaitsReopen: status.awaitsReopenForAudioRecording
        )
        return CheckPermissions(state)
    }

    /// A permission's Allow…, as anywhere else (`PermissionCenter.request`):
    /// macOS's prompt when it hasn't asked yet, else System Settings; for
    /// Automation with the app closed, the app, in the background.
    func requestCheckPermission(_ permission: CheckPermission, app: CheckableApp, current: CheckPermissions) async {
        guard let request = PermissionCenter.request(for: permission.permission(app: app.name), access: current.access(permission))
        else { return }
        await carryOut(request, app: app.bundleID) { _ = await AppReader.openInBackground(app) }
    }

    /// Add an App's check (`checkStarted`, `checkEnded`): for about three
    /// minutes it plays the app it checks and pauses and plays it again and
    /// again, judging it partly by Now Playing. AutoHush pausing and resuming
    /// the media player in its gaps would fade it in and out, make it the
    /// Now Playing app, and press the menu bar's Now Playing item along with
    /// the check when the player is controlled there. So while it runs,
    /// AutoHush resumes nothing: a player it paused stays paused until the
    /// check ends, then comes back as usual (`PlayerSession.holdResumes`).
    func holdsPlayerForCheck(_ held: Bool) {
        guard held != session.resumesHeld else { return }
        logger.info("Add an App’s check \(held ? "runs: AutoHush resumes nothing until it ends" : "ended: AutoHush resumes as usual", privacy: .public)")
        session.holdResumes(held)
        status.playerHeldForCheck = held
    }

    func reopenForAudioRecording() {
        noteAudioRecordingAllowedInSettings()
        reopen()
    }

    /// Keeps what the check found, then makes the app the player: chosen
    /// again when it was already (checked again, its new setup is used).
    func useCheckedApp(_ result: CheckResult, asksToReopen: Bool) {
        guard let setup = result.setup else { return }
        checkedPlayers.keep(result)
        logger.notice("Add an App: \(setup.name, privacy: .public) added, by \(setup.ways.map(\.logName).joined(separator: ", "), privacy: .public)")
        refreshPlayerOptions()
        chooseMusicPlayer(setup.bundleID, replacing: setup.bundleID == player?.bundleID, asksToReopen: asksToReopen)
    }
}

private extension PlayerSetup.Way {
    /// How the log names it (English).
    var logName: String {
        switch self {
        case .script: "AppleScript"
        case .menu(let name): "its menu \(name)"
        case .page: "its page"
        case .panel: "the Now Playing panel"
        case .mute: "muting it"
        }
    }
}
