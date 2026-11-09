import SwiftUI

/// A row of the menu that acts when clicked, as a menu item does: under the
/// pointer (or the arrow keys' highlight) it takes the tint (macOS's faint
/// grey, `.focusTint`), outlined where the keys put it, its words and
/// symbol as they are, as the rows of macOS's own menu bar menus (Sound,
/// Wi-Fi) light up (G2, the user's pick, 2026-11-06: "if you check the
/// menubar apps … it shows them in the grey"; in the accent color, its text
/// white, before, as an app's menus; a row with a grey second line took the
/// tint since D2c). Disabled, it's dimmed and stays dark. `tinted`: it
/// never lights up itself, the menu's tint shows behind it instead
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
        @Environment(\.keyHighlightByKeys) private var byKeys

        var body: some View {
            let lit = isEnabled && !tinted && (isHovered || showsKeyHighlight)
            configuration.label
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { if lit { HighlightTint(isFocused: true, byKeys: byKeys, cornerRadius: 6) } }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }
    }
}
