/// What a check needs allowed for the chosen app.
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
