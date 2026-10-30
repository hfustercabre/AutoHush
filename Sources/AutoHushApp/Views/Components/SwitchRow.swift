import SwiftUI

/// A title, an optional description under it, and a switch. VoiceOver
/// hears it as one: the switch, named by the title, the description its hint.
/// In Settings, the whole row takes the highlight (`highlightableRow`):
/// Return or Space turns the switch.
struct SwitchRow: View {
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool
    @FocusState private var isFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(title, subtitle: subtitle)
                .accessibilityHidden(true) // the switch says it
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { title }
                .toggleStyle(PillToggleStyle())
                .focused($isFocused)
                .focusEffectDisabled(keyboard != nil) // the row's tint shows it
                .accessibilityHint(subtitle ?? Text(verbatim: ""))
        }
        .highlightableRow(isFocused: isFocused, press: { isOn.toggle() })
    }
}
