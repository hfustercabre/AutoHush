import Foundation
import CheckedPlayers

// AddAppModel: the step that allows what the check needs, and the
// permissions read meanwhile.
extension AddAppModel {
    /// Reads the permissions about once a second while they're asked for,
    /// and goes on once they're all allowed (or with `continueWithoutAll`).
    func watchPermissions() {
        guard let app = chosen, let traits else { return }
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .allowing {
                await self.refreshPermissions(for: app, scriptable: traits.scriptable)
                // AutoHush read the change after all: as any missing permission.
                if !self.permissions.neededAllowed { self.accessibilityNeedsReopen = false }
                if self.permissions.allAllowed(antiDot: self.antiDot), !self.accessibilityNeedsReopen {
                    self.permissionMissingInCheck = false
                    self.afterPermissions()
                    return
                }
                await self.sleep(.seconds(1))
            }
        }
    }

    /// The Allow step's Continue, once what's needed is allowed: the check
    /// goes on without the rest, checking less.
    func continueWithoutAll() {
        guard stage == .allowing, permissions.neededAllowed, !accessibilityNeedsReopen else { return }
        stopWork()
        afterPermissions()
    }

    /// A permission's Allow…, then the permissions read again, so its row
    /// follows at once. Audio Recording turned on in System Settings applies
    /// once AutoHush reopens: the window then offers to.
    func request(_ permission: CheckPermission) {
        guard let app = chosen, let traits else { return }
        let current = permissions
        Task { [weak self] in
            guard let self else { return }
            await self.host?.requestCheckPermission(permission, app: app, current: current)
            guard self.chosen == app else { return }
            await self.refreshPermissions(for: app, scriptable: traits.scriptable)
        }
    }

    /// Reopen AutoHush, for Audio Recording: a finished check is kept.
    func reopenAutoHush() {
        host?.reopenForAudioRecording()
    }

    /// Reopen AutoHush, for Accessibility (`accessibilityNeedsReopen`).
    func reopenForAccessibility() {
        guard accessibilityNeedsReopen else { return }
        host?.reopenKeepingAddApp()
    }

    private func afterPermissions() {
        if needsReopen, reopenOutcome == nil {
            stage = .reopenAsked
        } else {
            waitForPlaying()
        }
    }

    /// Reads what the check of `app` needs, as it stands now, into
    /// `permissions`.
    func refreshPermissions(for app: CheckableApp, scriptable: Bool) async {
        permissions = await host?.checkPermissions(app, scriptable: scriptable) ?? CheckPermissions()
    }
}
