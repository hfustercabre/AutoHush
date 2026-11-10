import SwiftUI

/// A title, an optional description under it, and a switch. VoiceOver
/// hears it as one: the switch, named by the title, the description its hint.
/// In Settings, the whole row takes the highlight (`highlightableRow`):
/// Return or Space turns the switch, as a click anywhere in its tint does
/// (the user, 2026-11-03: a click on the row did nothing).
struct SwitchRow: View {
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool
    /// It stands for what another page's row opened: the highlight goes on
    /// from it (`KeyHighlight.highlightCurrent`).
    var isCurrent: (() -> Bool)?
    @FocusState private var isFocused: Bool
    /// VoiceOver's cursor on the row's control brings the highlight (K5-1).
    @AccessibilityFocusState private var controlHasVoiceOverCursor: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    init(_ title: Text, subtitle: Text? = nil, isOn: Binding<Bool>, isCurrent: (() -> Bool)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.isCurrent = isCurrent
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
                .accessibilityFocused($controlHasVoiceOverCursor)
        }
        .clickAnywhere { isOn.toggle() }
        .highlightableRow(isFocused: isFocused, press: { isOn.toggle() }, isCurrent: isCurrent,
                          voiceOverTarget: $controlHasVoiceOverCursor)
    }
}
