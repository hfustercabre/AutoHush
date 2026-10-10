import SwiftUI
import AutoHushKit

/// Settings → Fades, in a card like the menu's: a switch, and the fades'
/// lengths while it's on; dimmed for a player AutoHush can't fade. Restore
/// Defaults sets the fades back.
struct FadesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                Group {
                    SwitchRow(
                        Text("Fade playback", comment: "Settings → Fades: the switch that turns the fades on or off"),
                        subtitle: Text("Out before pausing, and back in when resuming.",
                                       comment: "Settings → Fades, under “Fade playback”"),
                        isOn: Binding(
                            get: { model.timings.fadesEnabled },
                            set: { enabled in
                                var timings = model.timings
                                timings.fadesEnabled = enabled
                                model.setTimings(timings)
                            }
                        )
                    )
                    // The lengths show only while there's something to fade.
                    if model.timings.fadesEnabled && model.playerCanFade {
                        CardDivider()
                        TimingSliderRow(
                            model: model,
                            title: Text("Fade out before pausing", comment: "Settings → Fades: slider for how long playback fades out before it pauses"),
                            keyPath: \.fadeOutDuration, range: TimingSettings.fadeDurationRange, step: 0.5,
                            help: Text("How long playback fades out before it pauses. 0 pauses it at once.",
                                       comment: "Settings → Fades, under “Fade out before pausing”")
                        )
                        CardDivider()
                        TimingSliderRow(
                            model: model,
                            title: Text("Fade in when resuming", comment: "Settings → Fades: slider for how long playback fades back in when it resumes"),
                            keyPath: \.fadeInDuration, range: TimingSettings.fadeDurationRange, step: 0.5,
                            help: Text("How long playback takes to fade back in once it resumes. 0 resumes at full volume.",
                                       comment: "Settings → Fades, under “Fade in when resuming”")
                        )
                    }
                }
                .disabled(!model.playerCanFade)
                .opacity(model.playerCanFade ? 1 : 0.45) // a disabled switch alone barely shows it
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can't change its volume.",
                                     comment: "Settings → Fades, under the dimmed fade settings; %@ is the media player, e.g. TIDAL"),
                              kind: .info)
                }
            }
            RestoreDefaultsButton(isDefault: model.fadesAreDefaults) { model.restoreDefaultFades() }
        }
    }
}
