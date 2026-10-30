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
                .environment(\.menuRowIsLit, lit)
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

extension EnvironmentValues {
    /// Inside a lit `MenuRowButtonStyle` row: its secondary text turns white too.
    @Entry var menuRowIsLit = false
}

/// Secondary text in a menu row, white while the row is lit.
struct MenuRowSubtitle: View {
    let text: String
    @Environment(\.menuRowIsLit) private var isLit

    var body: some View {
        Text(verbatim: text)
            .font(.appCaption)
            .foregroundStyle(isLit ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.appSecondary))
    }
}
