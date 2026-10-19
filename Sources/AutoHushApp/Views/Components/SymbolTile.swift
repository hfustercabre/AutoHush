import SwiftUI

/// A symbol on a square tinted with the accent color: Settings' sidebar
/// shows its pages this way, a `PermissionRow` its permission, and the
/// check's warning the window's states.
struct SymbolTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.symbolTileFill)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .accessibilityHidden(true)
    }
}
