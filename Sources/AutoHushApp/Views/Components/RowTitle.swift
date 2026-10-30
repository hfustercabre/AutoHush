import SwiftUI

/// A row's title, with an optional description under it.
struct RowTitle: View {
    let title: Text
    var subtitle: Text?

    init(_ title: Text, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            if let subtitle {
                subtitle
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
