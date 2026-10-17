import SwiftUI

extension View {
    /// An option the current settings rule out, shown anyway: greyed out and
    /// unclickable (the user, 2026-10-17: options never hide). A disabled
    /// control alone barely shows it, hence the lower opacity.
    func unavailable(_ isUnavailable: Bool) -> some View {
        disabled(isUnavailable).opacity(isUnavailable ? 0.45 : 1)
    }
}
