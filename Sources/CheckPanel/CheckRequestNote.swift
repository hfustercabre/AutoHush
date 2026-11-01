import SwiftUI

/// What the check asks of the user (play, pause, allow), in its look's tint,
/// with more under it: the time left.
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
            Label(text, systemImage: symbol).fontWeight(.medium).foregroundStyle(look.requestTint)
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
