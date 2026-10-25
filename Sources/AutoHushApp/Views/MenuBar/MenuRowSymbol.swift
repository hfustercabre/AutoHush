import SwiftUI

/// A symbol as a menu row's picture, centered in the rows' picture column
/// (`MenuSpacing.row`) as their icons are, in grey (Ignored Apps' while
/// none is ignored).
struct MenuRowSymbol: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(.appSecondary)
            .frame(width: MenuSpacing.row.picture)
    }
}
