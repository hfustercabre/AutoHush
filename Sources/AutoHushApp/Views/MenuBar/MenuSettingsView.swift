import SwiftUI
import AutoHushKit

/// The menu's settings, below Ignored Apps, each part between lines (the
/// user, 2026-10-17: no cards): Detection's, Fades' and
/// Advanced's switches, each with its symbol (in the accent color while
/// it's on) and what it does in a few words; the chevron under them
/// unfolds the pages' names and the rest in their places: AntiDot mode's
/// ways under it (Detection's "Modes"), Detection's timings in a part of
/// their own ("Timing"), the fades' lengths under Fade playback. As in
/// Settings, what doesn't apply is greyed out, never hidden.
struct MenuSettingsView: View {
    let model: StatusMenuModel
    let settings: SettingsModel

    private var isOpen: Bool { model.showsMoreSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isOpen {
                pageName(.detection)
                innerTitle(Text("Modes", comment: "Settings → Detection and the menu: heading over AntiDot mode"))
            }
            part {
                switchRow(.antiDot)
                if isOpen {
                    ChoiceChips(
                        options: [DetectionMethod.playbackSignals, .openStreams].map { .init(title: $0.title, value: $0) },
                        selection: settings.detectionMethod,
                        onSelect: { settings.setDetectionMethod($0) }
                    )
                    .unavailable(!settings.isAntiDotMode)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
            if isOpen {
                line
                innerTitle(Text("Timing", comment: "Settings → Detection: heading of how long other apps must play or be quiet before your player pauses or resumes"))
                part {
                    slider(.pauseAfter)
                    slider(.resumeAfter)
                    slider(.silenceThreshold).unavailable(settings.isAntiDotMode)
                }
            }
            line
            if isOpen { pageName(.fades) }
            part {
                switchRow(.fades)
                if isOpen {
                    Group {
                        slider(.fadeOut)
                        slider(.fadeIn)
                    }
                    .unavailable(!settings.timings.fadesEnabled && settings.playerCanFade)
                }
            }
            line
            if isOpen { pageName(.advanced) }
            part {
                switchRow(.levelsMusic)
            }
            line
            part {
                switchRow(.staysPausedAfterCalls)
            }
            chevron
        }
        .frame(width: menuContentWidth)
    }

    /// A part's rows, inset as the menu's other rows.
    private func part<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
    }

    /// The line between the parts, as between the menu's own parts.
    private var line: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .transition(.opacity)
    }

    /// One of the switches: its symbol, its name and what it does, and the switch.
    private func switchRow(_ kind: SettingsSwitch) -> some View {
        let isOn = kind.isOn(settings)
        return HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.appSecondary))
                .frame(width: 22)
                .accessibilityHidden(true)
            RowTitle(kind.title, subtitle: kind.shortExplanation)
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { kind.isOn(settings) }, set: { kind.set($0, in: settings) })) { kind.title }
                .toggleStyle(PillToggleStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .unavailable(kind.isUnavailable(settings))
    }

    private func slider(_ timing: SettingsTiming) -> some View {
        TimingSliderRow(model: settings, timing: timing, compact: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .transition(.opacity)
    }

    /// A Settings page's name over its part (unfolded only).
    private func pageName(_ page: SettingsWindowController.Page) -> some View {
        SectionLabel(Text(verbatim: page.title))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .transition(.opacity)
    }

    /// A title inside a page's part ("Modes", "Timing"): smaller and lighter.
    private func innerTitle(_ title: Text) -> some View {
        title
            .textCase(.uppercase)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .transition(.opacity)
    }

    /// A small chevron on a pill (C3), centered: down while folded, up while not.
    private var chevron: some View {
        Button { model.perform(.toggleMoreSettings) } label: {
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.appSecondary)
                .frame(width: 44, height: 16)
                .background(Capsule().fill(.chipFill))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: isOpen ? Self.hideTitle : Self.showTitle))
        .accessibilityLabel(Text(verbatim: isOpen ? Self.hideTitle : Self.showTitle))
    }

    static var showTitle: String {
        String(localized: "Show More Settings", comment: "Menu: the chevron below Ignored Apps that shows Detection’s, Fades’ and Advanced’s settings (its tooltip and VoiceOver label)")
    }

    static var hideTitle: String {
        String(localized: "Hide More Settings", comment: "Menu: the chevron that folds Detection’s, Fades’ and Advanced’s settings away again (its tooltip and VoiceOver label)")
    }
}
