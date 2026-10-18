import SwiftUI
import AutoHushKit

/// The menu's settings, below Ignored Apps, each part between lines (the
/// user, 2026-10-17: no cards) under its page's title (2026-10-18):
/// Detection's, Fades' and Advanced's switches, each with its symbol (in
/// the accent color while it's on) and what it does in a few words. A part
/// with more than its switches has a small chevron pill under it (F3, the
/// user's pick, 2026-10-18) that unfolds the rest in its place: AntiDot
/// mode's ways under it ("Modes") and Detection's timings ("Timing"); the
/// fades' lengths under Fade playback. Advanced has nothing more. As in
/// Settings, what doesn't apply is greyed out, never hidden, saying why.
struct MenuSettingsView: View {
    let model: StatusMenuModel
    let settings: SettingsModel

    private func isOpen(_ part: MenuSettingsPart) -> Bool { model.unfoldedSettings.contains(part) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageName(.detection)
            if isOpen(.detection) {
                innerTitle(Text("Modes", comment: "Settings → Detection and the menu: heading over AntiDot mode"))
            }
            part {
                switchRow(.antiDot)
                if isOpen(.detection) {
                    ChoiceChips(
                        label: DetectionSettingsView.detectByTitle,
                        options: [DetectionMethod.playbackSignals, .openStreams].map { .init(title: $0.title, value: $0) },
                        selection: settings.detectionMethod,
                        onSelect: { settings.setDetectionMethod($0) }
                    )
                    .controlSize(.small) // C2: both words fit
                    .unavailable(!settings.isAntiDotMode)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
            if isOpen(.detection) {
                line
                innerTitle(Text("Timing", comment: "Settings → Detection: heading of how long other apps must play or be quiet before your player pauses or resumes"))
                part {
                    slider(.pauseAfter)
                    slider(.resumeAfter)
                    slider(.silenceThreshold).unavailable(settings.isAntiDotMode)
                }
            }
            chevron(.detection, page: .detection)
            line
            pageName(.fades)
            part {
                switchRow(.fades)
                if isOpen(.fades) {
                    Group {
                        slider(.fadeOut)
                        slider(.fadeIn)
                    }
                    .unavailable(!settings.playerCanFade || !settings.timings.fadesEnabled)
                }
            }
            chevron(.fades, page: .fades)
            line
            pageName(.advanced)
            part {
                switchRow(.levelsMusic)
            }
            line
            part {
                switchRow(.staysPausedAfterCalls)
            }
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

    /// One of the switches: its symbol, its name and what it does, and the
    /// switch; dimmed while it can't be changed, with why on a line of its
    /// own under it, undimmed (R2, the user's pick, 2026-10-18), and in its
    /// tooltip and VoiceOver hint.
    private func switchRow(_ kind: SettingsSwitch) -> some View {
        let isOn = kind.isOn(settings)
        let reason = kind.unavailableReason(settings)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.appSecondary))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                RowTitle(kind.title, subtitle: kind.shortExplanation)
                Spacer(minLength: 8)
                Toggle(isOn: Binding(get: { kind.isOn(settings) }, set: { kind.set($0, in: settings) })) { kind.title }
                    .toggleStyle(PillToggleStyle())
                    .accessibilityHint(reason.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
            }
            .unavailable(kind.isUnavailable(settings))
            if let reason {
                Label(reason, systemImage: "info.circle")
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
                    .accessibilityHidden(true) // the switch's hint says it
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .help(reason.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
    }

    private func slider(_ timing: SettingsTiming) -> some View {
        TimingSliderRow(model: settings, timing: timing, compact: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .transition(.opacity)
    }

    /// A Settings page's name over its part.
    private func pageName(_ page: SettingsWindowController.Page) -> some View {
        SectionLabel(Text(verbatim: page.title))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .transition(.opacity)
    }

    /// A title inside a page's part ("Modes", "Timing"): a description's size, grey.
    private func innerTitle(_ title: Text) -> some View {
        title
            .font(.appCaption)
            .foregroundStyle(.appSecondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .transition(.opacity)
    }

    /// A small chevron on a pill (C3), centered under a part: down while
    /// its other settings are folded, up while they show.
    private func chevron(_ part: MenuSettingsPart, page: SettingsWindowController.Page) -> some View {
        let title = isOpen(part) ? Self.hideTitle : Self.showTitle
        return Button { model.perform(.toggleSettings(part)) } label: {
            Image(systemName: isOpen(part) ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.appSecondary)
                .frame(width: 44, height: 16)
                .background(Capsule().fill(.chipFill))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: title))
        // Two of them: VoiceOver hears whose.
        .accessibilityLabel(Text(verbatim: "\(page.title), \(title)"))
    }

    static var showTitle: String {
        String(localized: "Show More Settings", comment: "Menu: the chevron under Detection’s or Fades’ switch that shows the rest of that part’s settings (its tooltip; VoiceOver says the part’s name before it)")
    }

    static var hideTitle: String {
        String(localized: "Hide More Settings", comment: "Menu: the chevron that folds the rest of Detection’s or Fades’ settings away again (its tooltip; VoiceOver says the part’s name before it)")
    }
}
