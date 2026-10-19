import SwiftUI

/// A symbol as a menu row's picture, centered in the rows' picture column
/// (`MenuSpacing.row`) as their icons are: grey, or in the accent color
/// while what it stands for is on (a setting's switch).
struct MenuRowSymbol: View {
    let name: String
    var isOn = false

    init(_ name: String, isOn: Bool = false) {
        self.name = name
        self.isOn = isOn
    }

    var body: some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.appSecondary))
            .frame(width: MenuSpacing.row.picture)
    }
}
