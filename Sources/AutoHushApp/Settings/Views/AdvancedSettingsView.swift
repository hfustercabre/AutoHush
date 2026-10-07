import SwiftUI
import AutoHushKit

/// Settings → Advanced, in cards like the menu's: Detection (when another
/// app counts as playing or stopped, and the silence threshold), Fades
/// (dimmed for a player AutoHush can't fade) and Restore Defaults.
struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(Text("Detection", comment: "Settings → Advanced: heading of when other apps count as playing or stopped"))
            Card {
                slider(
                    Text("Pause music after", comment: "Settings → Advanced and Diagnostics: how long another app must play before the music pauses"),
                    value: \.startConfirmation, range: TimingSettings.startConfirmationRange, step: 0.25,
                    format: seconds,
                    help: Text("How long another app must be audible. Filters out short sounds apps play themselves; system notification sounds are always ignored.",
                               comment: "Settings → Advanced, under “Pause music after”")
                )
                CardDivider()
                slider(
                    Text("Resume music after", comment: "Settings → Advanced and Diagnostics: how long other apps must be quiet before the music resumes"),
                    value: \.stopGrace, range: TimingSettings.stopGraceRange, step: 0.5,
                    format: seconds,
                    help: Text("How long another app must be silent. Bridges gaps between tracks and videos.",
                               comment: "Settings → Advanced, under “Resume music after”")
                )
                CardDivider()
                slider(
                    Text("Silence threshold", comment: "Settings → Advanced and Diagnostics: the sound level below which an app counts as silent"),
                    value: \.silenceThresholdDB, range: TimingSettings.silenceThresholdRange, step: 5,
                    format: { String(localized: "\(Int($0)) dB", comment: "A sound level in decibels") },
                    help: Text("Quieter output counts as silence. Only used while measuring audio levels (AntiDot mode off).",
                               comment: "Settings → Advanced, under “Silence threshold”")
                )
            }

            SectionHeading(Text("Fades", comment: "Settings → Advanced: heading of the fade out and fade in settings"))
            Card {
                Group {
                    slider(
                        Text("Fade out before pausing", comment: "Settings → Advanced: slider for how long the music fades out before it pauses"),
                        value: \.fadeOutDuration, range: TimingSettings.fadeDurationRange, step: 0.5,
                        format: seconds,
                        help: Text("How long the music fades out before it pauses. 0 pauses it at once.",
                                   comment: "Settings → Advanced, under “Fade out before pausing”")
                    )
                    CardDivider()
                    slider(
                        Text("Fade in when resuming", comment: "Settings → Advanced: slider for how long the music fades back in when it resumes"),
                        value: \.fadeInDuration, range: TimingSettings.fadeDurationRange, step: 0.5,
                        format: seconds,
                        help: Text("How long the music takes to fade back in once it resumes. 0 resumes at full volume.",
                                   comment: "Settings → Advanced, under “Fade in when resuming”")
                    )
                }
                .disabled(!model.playerCanFade)
                .opacity(model.playerCanFade ? 1 : 0.45) // a disabled slider alone barely shows it
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can't change its volume.",
                                     comment: "Settings → Advanced, under the dimmed fade settings; %@ is the music player, e.g. TIDAL"),
                              kind: .info)
                }
            }

            HStack {
                Spacer()
                Button { model.restoreDefaultTimings() } label: {
                    Text("Restore Defaults", comment: "Settings → Advanced: button that sets every timing back to its default")
                }
                    .buttonStyle(.chip)
                    .disabled(model.timings == .defaults)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func seconds(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "\(number) s", comment: "A duration in seconds")
    }

    private func slider(
        _ title: Text,
        value keyPath: WritableKeyPath<TimingSettings, Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        help: Text
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                title
                Spacer()
                Text(format(model.timings[keyPath: keyPath]))
                    .monospacedDigit()
                    .foregroundStyle(.appSecondary)
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
            help.captionStyle()
        }
    }
}
