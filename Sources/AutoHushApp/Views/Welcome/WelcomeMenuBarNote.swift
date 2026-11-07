import SwiftUI

/// Beside the welcome's Done: the menu bar icon people will see, then where
/// AutoHush stays once the window closes (F1a, the user's pick, 2026-11-02),
/// so closing it doesn't look like quitting.
struct WelcomeMenuBarNote: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: MenuBarIcon.noMusic.image())
                .renderingMode(.template)
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            Text(verbatim: Self.text)
                .font(.appCallout)
                .foregroundStyle(.appSecondary)
                .fixedSize()
        }
    }

    static var text: String {
        String(localized: "AutoHush is now in the menu bar.",
               comment: "Welcome window, beside Done on its permissions page, after AutoHush's menu bar icon: AutoHush keeps running there once the window closes")
    }
}
