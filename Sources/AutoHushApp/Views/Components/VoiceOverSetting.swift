import AppKit
import SwiftUI

/// Whether VoiceOver is on, read when a view acts on it (a press, a
/// highlight arriving), not as it's drawn: macOS's setting, unless the
/// window's owner gives its own (tests, whose results then don't follow
/// the test Mac's VoiceOver; the full check, 2026-11-06, T-1). A class,
/// so the environment compares it by identity, as it can't a closure.
final class VoiceOverSetting: Sendable {
    let isOn: @MainActor @Sendable () -> Bool

    init(isOn: @escaping @MainActor @Sendable () -> Bool) {
        self.isOn = isOn
    }

    /// macOS's.
    static let system = VoiceOverSetting { NSWorkspace.shared.isVoiceOverEnabled }
}

extension EnvironmentValues {
    /// VoiceOver on or off, as the views read it (`VoiceOverSetting`).
    @Entry var voiceOver = VoiceOverSetting.system
}
