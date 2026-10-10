import AppKit
import AutoHushKit

/// Where a permission stands, read without asking for it.
enum PermissionAccess: Equatable, Sendable {
    case allowed
    /// macOS hasn't asked yet: asking shows its own prompt.
    case notAsked
    /// Not allowed: only System Settings changes it.
    case denied
    /// Automation can only be asked for while the player runs, and AutoHush
    /// never opens it by itself.
    case playerNotRunning
    /// Allowed in System Settings, but macOS applies Audio Recording only from
    /// AutoHush's next launch.
    case needsReopen
    /// Not used: Audio Recording in AntiDot mode.
    case notNeeded

    var isSatisfied: Bool { self == .allowed || self == .notNeeded }
}

/// What AutoHush needs to work for the chosen player, as it stands: the
/// player's control permission, and Audio Recording unless AntiDot mode is on.
struct PermissionsState: Equatable, Sendable {
    /// The chosen player's control permission; `nil` with no player chosen.
    var control: Permission?
    var controlAccess: PermissionAccess = .allowed
    var audio: PermissionAccess = .allowed
    /// Accessibility, whatever the player: adding a web app drives Safari with it.
    var accessibility = true

    /// Nothing missing: windows that wait for the permissions go on.
    var allSatisfied: Bool { controlAccess.isSatisfied && audio.isSatisfied }
}

/// What a click on a missing permission's button does.
enum PermissionRequest: Equatable, Sendable {
    /// Shows macOS's own prompt: it hasn't asked yet.
    case askMacOS(Permission)
    /// Opens where it's switched on in System Settings.
    case openSettings(SystemSettingsPane)
    /// Opens the player, so macOS can ask for Automation.
    case openPlayer
    /// Quits and opens AutoHush again, so macOS applies Audio Recording.
    case reopen
}

/// Reads the permissions AutoHush needs, without asking, often enough for
/// windows to follow them (about once a second while one shows), and turns a
/// click on a missing one into the right request.
@MainActor
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
        var runningPID: @MainActor (String) -> pid_t? = { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }?.processIdentifier
        }
        var audio: @MainActor () -> AudioCapturePermission? = { TCCAudioCapturePermission().status() }
        var requestAudio: @MainActor (@escaping @Sendable (Bool) -> Void) -> Void = { TCCAudioCapturePermission().request(completion: $0) }
        var openPane: @MainActor (SystemSettingsPane) -> Void = { $0.open() }
    }

    private let system: System
    /// Reading and asking for Automation block: it's done here.
    nonisolated static let queue = DispatchQueue(label: "AutoHush.Permissions", qos: .userInitiated)

    init(system: System = System()) {
        self.system = system
    }

    /// The permissions for `player` as they stand. `detection` is what
    /// AutoHush's monitoring uses now, for when macOS can't tell about Audio
    /// Recording; `awaitsReopen`: the user went to allow it in System
    /// Settings during this launch.
    func state(player: (any MusicPlayer)?, detectionMethod: DetectionMethod, detection: DetectionMode,
               awaitsReopen: Bool) async -> PermissionsState {
        var state = PermissionsState(accessibility: system.isTrusted())
        if let player {
            state.control = player.controlPermission
            state.controlAccess = await controlAccess(player)
        }
        state.audio = audioAccess(detectionMethod: detectionMethod, detection: detection, awaitsReopen: awaitsReopen)
        return state
    }

    private func controlAccess(_ player: any MusicPlayer) async -> PermissionAccess {
        switch player.controlPermission {
        case .accessibility:
            return system.isTrusted() ? .allowed : .denied
        case .automation:
            guard let pid = system.runningPID(player.bundleID) else { return .playerNotRunning }
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
        guard detectionMethod == .audioLevels else { return .notNeeded }
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

    /// Carries out `request`. Asking for Accessibility shows macOS's prompt
    /// and opens System Settings, where it's switched on; asking for
    /// Automation waits for the user's answer to macOS's prompt.
    /// The app with `bundleID` is running.
    func isRunning(_ bundleID: String) -> Bool {
        system.runningPID(bundleID) != nil
    }

    func perform(_ request: PermissionRequest, player: (any MusicPlayer)?) async {
        switch request {
        case .askMacOS(.accessibility):
            system.promptAccessibility()
            system.openPane(.accessibility)
        case .askMacOS(.automation):
            guard let player, let pid = system.runningPID(player.bundleID) else { return }
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
