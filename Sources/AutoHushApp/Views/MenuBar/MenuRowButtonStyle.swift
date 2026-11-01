import SwiftUI

/// A row of the menu that acts when clicked, as a menu item does: under the
/// pointer (or the arrow keys' highlight) it lights up in the accent color,
/// its text turning white; disabled, it's dimmed and stays dark. `tinted`:
/// it never lights up itself, the menu's tint shows behind it instead
/// (`HighlightableControl`; the players' side window, the user, 2026-10-18).
struct MenuRowButtonStyle: ButtonStyle {
    var tinted = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, tinted: tinted)
    }

    private struct Row: View {
        let configuration: Configuration
        let tinted: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.showsKeyHighlight) private var showsKeyHighlight

        var body: some View {
            let lit = isEnabled && !tinted && (isHovered || showsKeyHighlight)
            configuration.label
                .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(lit ? AnyShapeStyle(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)) : AnyShapeStyle(.clear)))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }
    }
}

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
