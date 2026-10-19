import SwiftUI

/// A permission as a row, in the welcome window and Add an App's step 2:
/// its symbol on a tinted square (`SymbolTile`), its name (`badge` after
/// it: Needed, Optional) with what it's for or how it stands under it, then
/// "Allowed" after a check once it's allowed, or `trailing` while it isn't
/// (the way to allow it).
struct PermissionRow<Badge: View, Trailing: View>: View {
    let symbol: String
    let title: String
    let note: String
    let isAllowed: Bool
    let badge: Badge
    let trailing: Trailing

    init(symbol: String, title: String, note: String, isAllowed: Bool,
         @ViewBuilder badge: () -> Badge, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.note = note
        self.isAllowed = isAllowed
        self.badge = badge()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: title)
                    badge
                }
                Text(verbatim: note).captionStyle()
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if isAllowed {
                AllowedLabel()
            } else {
                trailing
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension PermissionRow where Badge == EmptyView {
    init(symbol: String, title: String, note: String, isAllowed: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.init(symbol: symbol, title: title, note: note, isAllowed: isAllowed, badge: { EmptyView() }, trailing: trailing)
    }
}

/// "Allowed" after a check: a permission that's allowed. Green is for the
/// symbol only: as text it's too faint in light mode.
struct AllowedLabel: View {
    var body: some View {
        Label {
            Text(verbatim: PermissionText.allowed)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
        }
        .font(.appCallout)
        .foregroundStyle(.appSecondary)
        .fixedSize()
    }
}
