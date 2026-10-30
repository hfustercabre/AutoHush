import SwiftUI

/// A note in orange on a light orange box: what needs doing (a permission,
/// a relaunch, what the check asks), with its buttons under it. The window's
/// notes in the body's font; the panel's smaller, in the callout's.
struct WarningNote<Buttons: View>: View {
    let text: String
    let systemImage: String
    var font: Font = .body.weight(.medium)
    var padding: CGFloat = 10
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: systemImage)
                .font(font)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension WarningNote where Buttons == EmptyView {
    /// A note with no buttons.
    init(text: String, systemImage: String, font: Font = .body.weight(.medium), padding: CGFloat = 10) {
        self.init(text: text, systemImage: systemImage, font: font, padding: padding) { EmptyView() }
    }
}
