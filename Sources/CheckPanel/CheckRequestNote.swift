import SwiftUI

/// What the check asks of the user (play, pause, allow): its symbol in its
/// look's tint, its words in the primary color (D5a, the a11y audit's D5,
/// the user's pick, 2026-11-06: tinted words on the tint's fill read at
/// about 3.4:1), with more under it: the time left.
package struct CheckRequestNote: View {
    let text: String
    let detail: String
    let symbol: String
    let look: CheckPanelLook
    @Environment(\.colorSchemeContrast) private var contrast

    package init(_ text: String, detail: String, symbol: String, look: CheckPanelLook) {
        self.text = text
        self.detail = detail
        self.symbol = symbol
        self.look = look
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: text).foregroundStyle(.primary)
            } icon: {
                Image(systemName: symbol).foregroundStyle(look.requestTint)
            }
            .fontWeight(.medium)
            .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(verbatim: detail).font(look.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Outlined in its tint with Increase Contrast: the faint fill alone barely shows then.
            let shape = RoundedRectangle(cornerRadius: 8)
            shape.fill(look.requestFill)
                .overlay { if contrast == .increased { shape.strokeBorder(look.requestTint, lineWidth: 1) } }
        }
        .accessibilityElement(children: .combine)
    }
}
