import SwiftUI

/// A line between the menu's parts, where a menu has its separators,
/// 14 pt in from its sides.
struct MenuLine: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, MenuSpacing.lineVertical)
    }
}
