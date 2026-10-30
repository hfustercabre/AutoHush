import SwiftUI

/// A row of the menu with a switch (Playing Now's and the ignored apps'
/// apps): its picture in the rows' picture column (`MenuSpacing.row`), its
/// title with a few words under it, and macOS's small switch at its right,
/// named by `label` with `hint` after it, so VoiceOver makes the row one
/// stop. The arrow keys and the pointer highlight the row, Return or Space
/// turning it on or off, as a click anywhere on it does (the user,
/// 2026-10-21), and its switch takes the keyboard's focus (F5).
struct MenuSwitchRow<Picture: View, Title: View>: View {
    let isOn: Binding<Bool>
    /// The switch's name for VoiceOver: the row's title, or the app's name.
    let label: Text
    /// What VoiceOver says after it: what it does.
    let hint: Text
    let picture: Picture
    let title: Title
    @FocusState private var isFocused: Bool

    init(isOn: Binding<Bool>, label: Text, hint: Text,
         @ViewBuilder picture: () -> Picture, @ViewBuilder title: () -> Title) {
        self.isOn = isOn
        self.label = label
        self.hint = hint
        self.picture = picture()
        self.title = title()
    }

    var body: some View {
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
        // A click on its picture, its title or the room between turns it on
        // or off, as one on the switch, which takes its own clicks.
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
        .highlightableRow(isFocused: isFocused, press: { isOn.wrappedValue.toggle() })
    }
}
