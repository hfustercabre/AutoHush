import SwiftUI

/// Step 2's permissions: each one the chosen app's check needs, with what
/// it's for and Allow… until it's allowed. In AntiDot mode, Audio Recording
/// isn't used; allowed in System Settings, it waits for AutoHush to reopen.
struct CheckPermissionRows: View {
    let model: AddAppModel
    let app: String
    /// Accessibility's Allow… is the step's main control while it's missing.
    var focused: FocusState<AddAppModel.Step?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(symbol: "accessibility", title: AddAppText.accessibilityTitle, note: AddAppText.accessibilityUse(app),
                allowed: model.permissions.accessibility, permission: .accessibility)
            if model.antiDot {
                row(symbol: "waveform", title: PermissionText.audioTitle, note: AntiDotText.notNeeded,
                    allowed: nil, permission: .audioRecording)
            } else {
                row(symbol: "waveform", title: PermissionText.audioTitle,
                    note: model.audioAwaitsReopen ? AddAppText.audioAllowedAwaitsReopen : AddAppText.audioUse(app),
                    allowed: model.permissions.audio == .allowed, permission: .audioRecording)
            }
            if let automation = model.permissions.automation {
                row(symbol: "music.note", title: AddAppText.automationTitle, note: AddAppText.automationUse,
                    allowed: automation == .allowed, permission: .automation)
            }
        }
    }

    /// `allowed` nil: not used now (no button, nothing to allow).
    private func row(symbol: String, title: String, note: String, allowed: Bool?, permission: CheckPermission) -> some View {
        PermissionRow(symbol: symbol, title: title, note: note, isAllowed: allowed == true) {
            // Accessibility is needed (said while it's missing); the check
            // goes on without the others.
            if permission == .accessibility {
                if allowed == false { HeadingBadge(text: AddAppText.neededBadge) }
            } else if allowed != nil {
                Text(verbatim: AddAppText.optionalLabel).font(.appCaption).foregroundStyle(.appSecondary)
            }
        } trailing: {
            if allowed == false {
                if permission == .audioRecording, model.audioAwaitsReopen {
                    Button { model.reopenAutoHush() } label: { Text(verbatim: PermissionText.reopen) }
                        .buttonStyle(.chip)
                        .fixedSize()
                } else {
                    let allow = Button { model.request(permission) } label: { Text(verbatim: ButtonText.allow) }
                        .buttonStyle(.chip)
                        .fixedSize()
                        .accessibilityLabel(Text(verbatim: AddAppText.allowLabel(title)))
                    if permission == .accessibility { allow.focused(focused, equals: .allow) } else { allow }
                }
            }
        }
    }
}
