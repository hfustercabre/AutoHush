/// What a check needs allowed for the chosen app: its `PermissionsState`,
/// read by `PermissionCenter` as the chosen player's is, seen as the Allow
/// step's rows.
struct CheckPermissions: Equatable {
    var accessibility = false
    var audio = PermissionAccess.notAsked
    /// Automation for the app; `nil` when it can't be scripted.
    var automation: PermissionAccess?

    /// Everything the check can use is allowed (in AntiDot mode, Audio
    /// Recording isn't used).
    func allAllowed(antiDot: Bool) -> Bool {
        accessibility && (antiDot || audio == .allowed) && (automation == nil || automation == .allowed)
    }

    /// What the check can't go without: Accessibility (the app's menus, its
    /// page, the Now Playing panel, its window moved, the mouse and keyboard
    /// blocked). Without the others it checks less (`missingOptional`).
    var neededAllowed: Bool { accessibility }

    /// The ones not allowed that the check can go without.
    func missingOptional(antiDot: Bool) -> [CheckPermission] {
        (audio == .allowed || antiDot ? [] : [.audioRecording]) + (automation == nil || automation == .allowed ? [] : [.automation])
    }
}

extension CheckPermissions {
    /// The rows of `state`: Automation when the app is controlled through it.
    init(_ state: PermissionsState) {
        self.init(accessibility: state.accessibility, audio: state.audio,
                  automation: state.control == nil ? nil : state.controlAccess)
    }

    /// Where `permission` stands, for `PermissionCenter.request`.
    func access(_ permission: CheckPermission) -> PermissionAccess {
        switch permission {
        case .accessibility: accessibility ? .allowed : .denied
        case .audioRecording: audio
        case .automation: automation ?? .notNeeded
        }
    }
}
