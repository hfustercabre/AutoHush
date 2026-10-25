import AppKit
import SwiftUI

/// The row of buttons at the bottom of the menu: Settings (⌥-click:
/// Diagnostics), Updates, About and Quit.
struct MenuToolbarView: View {
    let model: StatusMenuModel

    var body: some View {
        HStack(spacing: 4) {
            button(Text(verbatim: Self.settingsTitle), symbol: "gearshape") {
                // As the menu used to offer it: ⌥ turns Settings into Diagnostics.
                NSEvent.modifierFlags.contains(.option) ? .showDiagnostics : .openSettings
            }
            let updates = UpdateOffer.updatesTitle
            button(Text(verbatim: model.isCheckingForUpdates ? UpdateOffer.checkingTitle : updates),
                   symbol: model.status.updateOffer == nil ? "arrow.down.circle" : "arrow.down.circle.fill",
                   tint: model.status.updateOffer == nil ? nil : .accentColor,
                   // Its filled, tinted symbol says an update waits: VoiceOver hears it.
                   spoken: model.status.updateOffer == nil || model.isCheckingForUpdates ? nil : AppStatus.withUpdate(updates)) { .updates }
                // Dimmed while the update installs, as its row above.
                .disabled(model.status.updateOffer?.state == .installing)
            button(Text(verbatim: SettingsWindowController.Page.about.title), symbol: "info.circle") { .showAbout }
            button(Text("Quit", comment: "Menu: button at the bottom; quits AutoHush"), symbol: "power") { .quit }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(width: menuContentWidth)
    }

    /// The button that opens Settings.
    static var settingsTitle: String {
        String(localized: "Settings", comment: "The menu: the button at the bottom that opens Settings")
    }

    private func button(_ title: Text, symbol: String, tint: Color? = nil, spoken: String? = nil,
                        command: @escaping @MainActor () -> StatusMenuCommand) -> some View {
        Button { model.perform(command()) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                    .accessibilityHidden(true) // the title says it
                title
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MenuSpacing.toolbarVertical)
        }
        .buttonStyle(ChipButtonStyle())
        .accessibilityLabel(spoken.map { Text(verbatim: $0) } ?? title)
    }
}
