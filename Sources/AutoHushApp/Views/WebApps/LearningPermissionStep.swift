import AppKit
import SwiftUI
import AutoHushKit

/// The permission learning needs first, as the checklist's step to do now
/// with its button under it: in the learning window and the Add a Web App
/// window, above the steps it locks.
struct LearningPermissionStep: View {
    let model: SettingsModel
    let permission: Permission
    let access: PermissionAccess
    let name: String

    var body: some View {
        let step = Self.step(permission, name: name)
        ChecklistStepRow(step: step, dimmed: false, bold: true, action: { _ in }) {
            StepSymbol(step: step)
        } accessory: {
            PermissionButton(model: model, permission: permission, access: access, long: true, prominent: true)
                .padding(.top, 2)
        }
    }

    /// Why the steps wait, under the permission.
    static func note(_ name: String) -> String {
        String(localized: "AutoHush needs it to see \(name)’s buttons. The steps below unlock once it’s allowed.",
               comment: "The learning window, under the permission it needs first; %@ is the web app")
    }

    /// The step: the permission to allow, why the steps wait under it.
    static func step(_ permission: Permission, name: String) -> ChecklistStep {
        ChecklistStep(title: permission.statusLine, notes: [note(name)], state: .current)
    }

    /// What VoiceOver announces while the steps wait: the permission, then
    /// why, as the step reads.
    static func announcement(_ permission: Permission, name: String) -> String {
        let step = step(permission, name: name)
        return ([step.title] + step.notes).joined(separator: "\n")
    }
}
