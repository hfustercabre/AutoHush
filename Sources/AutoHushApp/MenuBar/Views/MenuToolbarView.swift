import AppKit
import SwiftUI

/// The row of buttons at the bottom of the menu: Settings (⌥-click:
/// Diagnostics), Updates, About and Quit.
struct MenuToolbarView: View {
    let model: StatusMenuModel

    var body: some View {
        HStack(spacing: 4) {
            button(Text("Settings", comment: "Menu: button at the bottom; opens Settings"), symbol: "gearshape") {
                // As the menu used to offer it: ⌥ turns Settings into Diagnostics.
                NSEvent.modifierFlags.contains(.option) ? .showDiagnostics : .openSettings
            }
            button(Text("Updates"), symbol: model.status.updateOffer == nil ? "arrow.down.circle" : "arrow.down.circle.fill",
                   tint: model.status.updateOffer == nil ? nil : .accentColor) { .updates }
            button(Text("About", comment: "Menu: button at the bottom; shows About AutoHush"), symbol: "info.circle") { .showAbout }
            button(Text("Quit", comment: "Menu: button at the bottom; quits AutoHush"), symbol: "power") { .quit }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(width: menuContentWidth)
    }

    private func button(_ title: Text, symbol: String, tint: Color? = nil,
                        command: @escaping @MainActor () -> StatusMenuCommand) -> some View {
        Button { model.perform(command()) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                title
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
        .buttonStyle(MenuButtonStyle())
    }
}
