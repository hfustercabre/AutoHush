import SwiftUI

extension View {
    /// Descriptions and notes under a card or a control: small, grey, and
    /// on as many lines as they need.
    func captionStyle() -> some View {
        font(.appCaption)
            .foregroundStyle(.appSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
