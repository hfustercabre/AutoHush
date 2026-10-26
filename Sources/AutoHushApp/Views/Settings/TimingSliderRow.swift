import SwiftUI
import AutoHushKit

/// One of the timings as Settings → Fine-Tuning shows it: its title and value,
/// the slider, and what it does. It's changed as it's dragged.
struct TimingSliderRow: View {
    let model: SettingsModel
    let timing: SettingsTiming
    /// It stands for what's shown now (`KeyHighlight.highlightCurrent`):
    /// a row of the Fine-Tuning card a Behavior row opened.
    var isCurrent: (() -> Bool)?

    private var title: Text { timing.title }
    private var keyPath: WritableKeyPath<TimingSettings, Double> { timing.keyPath }

    @FocusState private var sliderFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                title
                Spacer(minLength: 4)
                Text(timing.format(model.timings[keyPath: keyPath]))
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
                in: timing.range,
                step: timing.step
            ) {
                title // what VoiceOver says for it; the row shows it above
            }
            .labelsHidden()
            .focused($sliderFocused)
            .focusEffectDisabled(keyboard != nil) // the row's tint shows it
            .accessibilityValue(Text(verbatim: timing.format(model.timings[keyPath: keyPath])))
            timing.help.captionStyle()
        }
        // Highlighted by the arrow keys (← and →
        // move it) and the pointer, and tinted while its slider has the
        // keyboard's focus (F5).
        .highlightableRow(isFocused: sliderFocused, adjust: step, isCurrent: isCurrent)
    }

    /// One step of the slider up (1) or down (-1), kept in its range.
    private func step(_ direction: Int) {
        var timings = model.timings
        let value = timings[keyPath: keyPath] + Double(direction) * timing.step
        timings[keyPath: keyPath] = min(max(value, timing.range.lowerBound), timing.range.upperBound)
        model.setTimings(timings)
    }
}
