import SwiftUI
import AutoHushKit

/// One of the timings as Settings → Detection and → Fades show it: its title
/// and value, the slider, and what it does; `compact` (the menu's More
/// Settings), smaller and without what it does. It's changed as it's dragged.
struct TimingSliderRow: View {
    let model: SettingsModel
    let timing: SettingsTiming
    var compact = false

    private var title: Text { timing.title }
    private var keyPath: WritableKeyPath<TimingSettings, Double> { timing.keyPath }

    @FocusState private var sliderFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 4) {
            HStack {
                title
                Spacer(minLength: 4)
                Text(timing.format(model.timings[keyPath: keyPath]))
                    .monospacedDigit()
                    .foregroundStyle(.appSecondary)
            }
            .font(compact ? .appCallout : nil)
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
            .controlSize(compact ? .small : .regular)
            .focused($sliderFocused)
            .focusEffectDisabled(keyboard != nil) // the row's tint shows it
            .accessibilityValue(Text(verbatim: timing.format(model.timings[keyPath: keyPath])))
            if !compact { timing.help.captionStyle() }
        }
        // In the menu and Settings, highlighted by the arrow keys (← and →
        // move it) and the pointer, and tinted while its slider has the
        // keyboard's focus (F5).
        .highlightableRow(isFocused: sliderFocused, adjust: step)
    }

    /// One step of the slider up (1) or down (-1), kept in its range.
    private func step(_ direction: Int) {
        var timings = model.timings
        let value = timings[keyPath: keyPath] + Double(direction) * timing.step
        timings[keyPath: keyPath] = min(max(value, timing.range.lowerBound), timing.range.upperBound)
        model.setTimings(timings)
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
                Text("Restore Defaults", comment: "Settings → Detection, → Fades and → Advanced: button that sets the page's settings back to their defaults")
            }
                .buttonStyle(.chip)
                .disabled(isDefault)
        }
        .padding(.top, 6)
    }
}
