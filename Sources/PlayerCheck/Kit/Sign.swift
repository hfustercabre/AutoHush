/// Whether a press took, judged by the surest sign the app showed before
/// it (`Look.surest`); with none, by its menu's word changing or its sound.
import AutoHushKit
package struct Sign: Sendable {
    let before: Look
    let kind: SignKind?

    package init(before: Look) {
        self.before = before
        kind = before.surest
    }

    package var byLevel: Bool { kind == .level }
    package func paused(_ now: Look) -> Bool {
        guard let kind else { return now.menuTitle != before.menuTitle || !now.sounding }
        return now.says(kind).map { $0 != .playing } ?? false
    }
    package func playing(_ now: Look) -> Bool {
        guard let kind else { return now.sounding }
        return now.says(kind) == .playing
    }
}
