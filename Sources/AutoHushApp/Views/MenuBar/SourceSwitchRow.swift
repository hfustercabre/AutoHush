import SwiftUI
import AutoHushKit

/// An app with sound and a switch for whether it pauses your player, as
/// Playing Now and the ignored apps' side window list them: its icon, its
/// name and what it does now (`MenuSwitchRow`); one stop for VoiceOver, the
/// switch named by the app, what it does its hint.
struct SourceSwitchRow: View {
    let model: StatusMenuModel
    let source: AudioSource
    /// Ignored, it says only that: the ignored apps' side window, whose
    /// title says the rest (the user, 2026-10-18: the line wrapped there).
    var saysIgnoredShortly = false
    /// Playing Now: an app that counts only because its sound is open says
    /// it may be paused (T8b, the user's pick, 2026-11-02).
    var playsNow = false

    /// What the row says under the app's name, what VoiceOver hears after
    /// it, and its help tag, if any.
    struct Words: Equatable {
        let subtitle: String
        let hint: String
        let help: String?
    }

    static func words(for source: AudioSource, isIgnored: Bool, mutes: Bool,
                      playsNow: Bool, saysIgnoredShortly: Bool) -> Words {
        if !isIgnored, playsNow, source.isOpenOutputOnly {
            return Words(subtitle: SourceText.soundOnLabel, hint: SourceText.soundOnHint, help: SourceText.soundOnHelp)
        }
        let subtitle = !isIgnored ? SourceText.interruptsLabel(mutes: mutes)
            : saysIgnoredShortly
            ? String(localized: "Ignored", comment: "The menu's Ignored Apps side window: under each app that is ignored (the side window's title already says what that means)")
            : IgnoredText.label
        return Words(subtitle: subtitle, hint: subtitle, help: nil)
    }

    var body: some View {
        let words = Self.words(for: source, isIgnored: model.status.isIgnored(source.id), mutes: model.status.mutesNow,
                               playsNow: playsNow, saysIgnoredShortly: saysIgnoredShortly)
        return MenuSwitchRow(isOn: Binding(get: { !model.status.isIgnored(source.id) },
                                           set: { model.perform(.setIgnored(source, !$0)) }),
                             label: Text(verbatim: source.name), hint: Text(verbatim: words.hint)) {
            Image(nsImage: AppIcon.image(for: source, players: model.status.playerOptions, size: 20))
                .resizable()
                .frame(width: 20, height: 20)
        } title: {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: source.name).lineLimit(1)
                Text(verbatim: words.subtitle)
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
            }
        }
        .help(words.help.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
    }
}
