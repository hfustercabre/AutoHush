import SwiftUI
import AutoHushKit

/// Settings → Advanced: Detection (when another app counts as playing or
/// stopped, and the silence threshold), Fades (dimmed for a player AutoHush
/// can't fade) and Restore Defaults.
struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                slider(
                    "Pause music after",
                    value: \.startConfirmation, range: TimingSettings.startConfirmationRange, step: 0.25,
                    format: seconds,
                    help: "How long another app must be audible. Filters out short sounds apps play themselves; system notification sounds are always ignored."
                )
                slider(
                    "Resume music after",
                    value: \.stopGrace, range: TimingSettings.stopGraceRange, step: 0.5,
                    format: seconds,
                    help: "How long another app must be silent. Bridges gaps between tracks and videos."
                )
                slider(
                    "Silence threshold",
                    value: \.silenceThresholdDB, range: TimingSettings.silenceThresholdRange, step: 5,
                    format: { String(localized: "\(Int($0)) dB", comment: "A sound level in decibels") },
                    help: "Quieter output counts as silence. Only used while measuring audio levels (AntiDot mode off)."
                )
            } header: {
                Text("Detection", comment: "Settings → Advanced: heading of when other apps count as playing or stopped")
            }

            Section {
                Group {
                    slider(
                        "Fade out before pausing",
                        value: \.fadeOutDuration, range: TimingSettings.fadeDurationRange, step: 0.5,
                        format: seconds,
                        help: "How long the music fades out before it pauses. 0 pauses it at once."
                    )
                    slider(
                        "Fade in when resuming",
                        value: \.fadeInDuration, range: TimingSettings.fadeDurationRange, step: 0.5,
                        format: seconds,
                        help: "How long the music takes to fade back in once it resumes. 0 resumes at full volume."
                    )
                }
                .disabled(!model.playerCanFade)
                .opacity(model.playerCanFade ? 1 : 0.45) // a disabled slider alone barely shows it
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can't change its volume.",
                                     comment: "Settings → Advanced, under the dimmed fade settings; %@ is the music player, e.g. TIDAL"),
                              kind: .info)
                }
            } header: {
                Text("Fades", comment: "Settings → Advanced: heading of the fade out and fade in settings")
            }

            Section {
                Button("Restore Defaults") { model.restoreDefaultTimings() }
                    .disabled(model.timings == .defaults)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func seconds(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "\(number) s", comment: "A duration in seconds")
    }

    private func slider(
        _ title: LocalizedStringKey,
        value keyPath: WritableKeyPath<TimingSettings, Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        help: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(format(model.timings[keyPath: keyPath]))
                    .monospacedDigit()
            }
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
            )
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
