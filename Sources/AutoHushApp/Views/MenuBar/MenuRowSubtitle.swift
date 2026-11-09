import SwiftUI

/// Secondary text in a menu row: the players' side window's, whose rows
/// never light up themselves (`tinted`), so it stays grey (K10, 2026-11-01:
/// its white for a lit row was never drawn). While the keys' highlight is
/// on the row, its `reason` in its place, if it has one (A13a).
struct MenuRowSubtitle: View {
    let text: String?
    var reason: String?
    @Environment(\.keyHighlightByKeys) private var byKeys

    var body: some View {
        if let shown = byKeys ? reason ?? text : text {
            Text(verbatim: shown)
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                // The reason on as many lines as it needs.
                .fixedSize(horizontal: false, vertical: byKeys && reason != nil)
        }
    }
}
