import AppKit
import AutoHushKit

/// Reads the permissions AutoHush needs, without asking, often enough for
/// windows to follow them (about once a second while one shows), and turns a
/// click on a missing one into the right request: for the chosen player, and
/// for the app Add an App checks, by the same rules. The chosen player's, as
/// last read, it keeps for the windows to show (`chosen`).
@MainActor
@Observable
final class PermissionCenter {
    /// The system calls, which tests replace.
    struct System {
        var isTrusted: @MainActor () -> Bool = { AccessibilityPermission.isTrusted() }
        /// Prompts for Accessibility (once per launch, macOS decides), which also
        /// lists AutoHush in System Settings.
        var promptAccessibility: @MainActor () -> Void = { _ = AccessibilityPermission.isTrusted(prompt: true) }
        /// `AutomationPermission.check` for the app running as the pid; `ask`
        /// shows macOS's prompt when it hasn't asked yet, and waits for it, on
        /// a queue of its own.
        var automation: @Sendable (pid_t, _ ask: Bool) async -> OSStatus = { pid, ask in
            await PermissionCenter.queue.run { AutomationPermission.check(pid: pid, ask: ask) }
        }
        var runningPID: @MainActor (String) -> pid_t? = { NSRunningApplication.running($0)?.processIdentifier }
        var audio: @MainActor () -> AudioCapturePermission? = { TCCAudioCapturePermission().status() }
        var requestAudio: @MainActor (@escaping @Sendable (Bool) -> Void) -> Void = { TCCAudioCapturePermission().request(completion: $0) }
        var openPane: @MainActor (SystemSettingsPane) -> Void = { $0.open() }
    }

    private let system: System
    /// Reading and asking for Automation block: it's done here.
    nonisolated static let queue = DispatchQueue(label: "AutoHush.Permissions", qos: .userInitiated)
    /// What AutoHush needs for the chosen player, as last read (`refresh`);
    /// the private harness sets it to draw a given state.
    var chosen = PermissionsState()

    init(system: System = System()) {
        self.system = system
    }

    /// Reads the chosen player's permissions again, and keeps them. Two
    /// reads may run at once (the menu opens, a player is chosen from it):
    /// one for a player that's no longer `chosenPlayer()` when it's done is
    /// dropped, so a slow read never leaves the previous player's
    /// permissions shown.
    func refresh(chosenPlayer: @MainActor () -> (any MusicPlayer)?, detectionMethod: DetectionMethod,
                 detection: DetectionMode, awaitsReopen: Bool) async {
        let player = chosenPlayer()
        let state = await state(player: player, detectionMethod: detectionMethod, detection: detection, awaitsReopen: awaitsReopen)
        guard chosenPlayer()?.bundleID == player?.bundleID else { return }
        if chosen != state { chosen = state }
    }

    /// The permissions for `player` as they stand. `detection` is what
    /// AutoHush's monitoring uses now, for when macOS can't tell about Audio
    /// Recording; `awaitsReopen`: the user went to allow it in System
    /// Settings during this launch.
    func state(player: (any MusicPlayer)?, detectionMethod: DetectionMethod, detection: DetectionMode,
               awaitsReopen: Bool) async -> PermissionsState {
        // One muted instead of paused needs only Audio Recording, its own row.
        let control = player?.controlPermission == .systemAudioRecording ? nil : player?.controlPermission
        return await state(app: player?.bundleID, control: control, detectionMethod: detectionMethod,
                           detection: detection, awaitsReopen: awaitsReopen)
    }

    /// The permissions for the app with bundle ID `app`, controlled through
    /// `control` (none: nothing to read for it); the rest as `state(player:…)`.
    func state(app: String?, control: Permission?, detectionMethod: DetectionMethod, detection: DetectionMode,
               awaitsReopen: Bool) async -> PermissionsState {
        var state = PermissionsState(player: app, accessibility: system.isTrusted())
        if let app, let control {
            state.control = control
            state.controlAccess = await controlAccess(control, app: app)
        }
        state.audio = audioAccess(detectionMethod: detectionMethod, detection: detection, awaitsReopen: awaitsReopen)
        return state
    }

    private func controlAccess(_ control: Permission, app: String) async -> PermissionAccess {
        switch control {
        case .accessibility:
            return system.isTrusted() ? .allowed : .denied
        case .automation:
            guard let pid = system.runningPID(app) else { return .playerNotRunning }
            return Self.access(automationStatus: await system.automation(pid, false))
        case .systemAudioRecording:
            return .allowed // never a player's control permission
        }
    }

    /// `AEDeterminePermissionToAutomateTarget`'s answer.
    nonisolated static func access(automationStatus status: OSStatus) -> PermissionAccess {
        switch AutomationPermission(status: status) {
        case .allowed: .allowed
        case .denied: .denied
        case .notAsked: .notAsked
        case .notRunning: .playerNotRunning
        }
    }

    private func audioAccess(detectionMethod: DetectionMethod, detection: DetectionMode, awaitsReopen: Bool) -> PermissionAccess {
        guard !detectionMethod.isAntiDot else { return .notNeeded }
        switch system.audio() {
        case .granted: return .allowed
        case .notDetermined: return .notAsked
        case .denied: return awaitsReopen ? .needsReopen : .denied
        case nil: return detection == .unavailable ? (awaitsReopen ? .needsReopen : .denied) : .allowed
        }
    }

    /// What a click on the button of `permission`, standing at `access`, does.
    nonisolated static func request(for permission: Permission, access: PermissionAccess) -> PermissionRequest? {
        switch (permission, access) {
        case (_, .allowed), (_, .notNeeded): nil
        case (.systemAudioRecording, .needsReopen): .reopen
        case (.automation, .playerNotRunning): .openPlayer
        case (.automation, .notAsked), (.systemAudioRecording, .notAsked): .askMacOS(permission)
        case (.accessibility, _): .askMacOS(permission) // prompts, then opens System Settings
        default: .openSettings(permission.settingsPane)
        }
    }

    /// The app with `bundleID` is running.
    func isRunning(_ bundleID: String) -> Bool {
        system.runningPID(bundleID) != nil
    }

    /// Carries out `request`, for the app with bundle ID `app`. Asking for
    /// Accessibility shows macOS's prompt and opens System Settings, where
    /// it's switched on; asking for Automation waits for the user's answer
    /// to macOS's prompt.
    func perform(_ request: PermissionRequest, app: String?) async {
        switch request {
        case .askMacOS(.accessibility):
            system.promptAccessibility()
            system.openPane(.accessibility)
        case .askMacOS(.automation):
            guard let app, let pid = system.runningPID(app) else { return }
            _ = await system.automation(pid, true)
        case .askMacOS(.systemAudioRecording):
            system.requestAudio { _ in }
        case .openSettings(let pane):
            system.openPane(pane)
        case .openPlayer, .reopen:
            break // the app opens the player, or reopens itself
        }
    }
}
