import AutoHushKit

/// One of `CheckPermissions`, for its Allow button.
enum CheckPermission: Equatable {
    case accessibility, audioRecording, automation

    /// As `PermissionCenter` knows it, for the app named `app`.
    func permission(app: String) -> Permission {
        switch self {
        case .accessibility: .accessibility(player: app)
        case .audioRecording: .systemAudioRecording
        case .automation: .automation(player: app)
        }
    }
}
