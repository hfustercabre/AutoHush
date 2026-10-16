import SwiftUI
import AutoHushKit

/// One of the timings as Settings → Detection and → Fades show it: its title
/// and value, the slider, and what it does.
struct TimingSliderRow: View {
    let model: SettingsModel
    let title: Text
    let keyPath: WritableKeyPath<TimingSettings, Double>
    let range: ClosedRange<Double>
    let step: Double
    var format: (Double) -> String = \.secondsText
    let help: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                title
                Spacer()
                Text(format(model.timings[keyPath: keyPath]))
                    .monospacedDigit()
                    .foregroundStyle(.appSecondary)
            }
            .accessibilityHidden(true) // the slider says both, as its label and value
            Slider(
                value: Binding(
                    get: { model.timings[keyPath: keyPath] },
                    set: { newValue in
                        var timings = model.timings
                        timings[keyPath: keyPath] = newValue
                        model.setTimings(timings)
                    }
                ),
                in: range,
                step: step
            ) {
                title // what VoiceOver says for it; the row shows it above
            }
            .labelsHidden()
            .accessibilityValue(Text(verbatim: format(model.timings[keyPath: keyPath])))
            help.captionStyle()
        }
    }
}

/// A page's Restore Defaults, under its cards on the right: it sets the
/// page's own settings back, and is dimmed while they're the defaults.
struct RestoreDefaultsButton: View {
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Text("Restore Defaults", comment: "Settings → Detection and → Fades: button that sets the page's settings back to their defaults")
            }
                .buttonStyle(.chip)
                .disabled(isDefault)
        }
        .padding(.top, 6)
    }
}
