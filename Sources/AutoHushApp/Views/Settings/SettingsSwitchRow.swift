import SwiftUI

/// One of `SettingsSwitch`, with what it does under it (`showsSubtitle`).
struct SettingsSwitchRow: View {
    let model: SettingsModel
    let kind: SettingsSwitch
    var showsSubtitle = true

    var body: some View {
        SwitchRow(kind.title, subtitle: showsSubtitle ? kind.subtitle : nil,
                  isOn: Binding(get: { kind.isOn(model) }, set: { kind.set($0, in: model) }))
            .unavailable(kind.isUnavailable(model)) // dimmed whole, not only its switch
    }
}
