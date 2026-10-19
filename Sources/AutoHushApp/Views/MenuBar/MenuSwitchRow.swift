import SwiftUI

/// A row of the menu with a switch (the settings' switches, Playing Now's
/// and the ignored apps' apps): its picture in the rows' picture column
/// (`MenuSpacing.row`), its title with a few words under it, and macOS's
/// small switch at its right, named by `label` with `hint` after it, so
/// VoiceOver makes the row one stop. The arrow keys and the pointer
/// highlight the row, Return or Space turning it on or off, and its switch
/// takes the keyboard's focus (F5). While it can't be changed it's greyed
/// out, with why on a line of its own under it, not greyed out (R2, the
/// user's pick, 2026-10-18).
struct MenuSwitchRow<Picture: View, Title: View>: View {
    let isOn: Binding<Bool>
    /// The switch's name for VoiceOver: the row's title, or the app's name.
    let label: Text
    /// What VoiceOver says after it: what it does, or why it can't be changed.
    let hint: Text
    var isUnavailable = false
    /// Why it can't be changed, under it.
    var reason: String?
    /// The tint's room around the row, out of its layout.
    var outset = CGSize(width: 6, height: 3)
    let picture: Picture
    let title: Title
    @FocusState private var isFocused: Bool

    init(isOn: Binding<Bool>, label: Text, hint: Text, isUnavailable: Bool = false, reason: String? = nil,
         outset: CGSize = CGSize(width: 6, height: 3),
         @ViewBuilder picture: () -> Picture, @ViewBuilder title: () -> Title) {
        self.isOn = isOn
        self.label = label
        self.hint = hint
        self.isUnavailable = isUnavailable
        self.reason = reason
        self.outset = outset
        self.picture = picture()
        self.title = title()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MenuSpacing.row.gap) {
                picture
                    .frame(width: MenuSpacing.row.picture)
                    .accessibilityHidden(true)
                title
                    .accessibilityHidden(true) // the switch says it: one stop for VoiceOver
                Spacer(minLength: 8)
                Toggle(isOn: isOn) { label }
                    .toggleStyle(PillToggleStyle())
                    .controlSize(MenuSpacing.switchSize)
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .accessibilityHint(hint)
            }
            .unavailable(isUnavailable)
            if let reason {
                Label(reason, systemImage: "info.circle")
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, MenuSpacing.row.text - MenuSpacing.row.leading) // under the title
                    .accessibilityHidden(true) // the switch's hint says it
            }
        }
        .highlightableRow(isFocused: isFocused, isAvailable: !isUnavailable,
                          horizontal: outset.width, vertical: outset.height,
                          press: { isOn.wrappedValue.toggle() })
    }
}
