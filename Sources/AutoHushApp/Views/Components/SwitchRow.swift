import SwiftUI

/// A title, an optional description under it, and a switch. VoiceOver
/// hears it as one: the switch, named by the title, the description its hint.
struct SwitchRow: View {
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool

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
                .accessibilityHint(subtitle ?? Text(verbatim: ""))
        }
    }
}

/// A row's title, with an optional description under it.
struct RowTitle: View {
    let title: Text
    var subtitle: Text?

    init(_ title: Text, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
            if let subtitle {
                subtitle
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
