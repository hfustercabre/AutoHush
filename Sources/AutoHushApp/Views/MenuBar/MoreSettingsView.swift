import SwiftUI
import AutoHushKit

/// Settings → Detection's, → Fades' and → Advanced's switches and timings,
/// folded away under a small chevron on a pill (C3) below Ignored Apps:
/// folded at first, then as the user left it while AutoHush runs. As in
/// Settings, only what applies shows: the fades' lengths while they're on,
/// AntiDot mode's ways while it's on, the silence threshold while it's off.
struct MoreSettingsView: View {
    let model: StatusMenuModel
    let settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.showsMoreSettings { content }
            chevron
        }
        .padding(.horizontal, 14)
        .padding(.top, model.showsMoreSettings ? 6 : 2)
        .padding(.bottom, 2)
        .frame(width: menuContentWidth)
        // Its row follows its height when rows show or hide.
        .onChange(of: layout) { model.perform(.fitMoreSettings) }
    }

    /// What decides which rows show.
    private var layout: [Bool] {
        [model.showsMoreSettings, settings.isAntiDotMode, settings.timings.fadesEnabled, settings.playerCanFade]
    }

    @ViewBuilder private var content: some View {
        SectionLabel(Text(verbatim: SettingsWindowController.Page.detection.title))
            .accessibilityAddTraits(.isHeader)
        SettingsSwitchRow(model: settings, kind: .antiDot, showsSubtitle: false)
        if settings.isAntiDotMode {
            ChoiceChips(
                options: [DetectionMethod.playbackSignals, .openStreams].map { .init(title: $0.title, value: $0) },
                selection: settings.detectionMethod,
                onSelect: { settings.setDetectionMethod($0) }
            )
        }
        TimingSliderRow(model: settings, timing: .pauseAfter, compact: true)
        TimingSliderRow(model: settings, timing: .resumeAfter, compact: true)
        if !settings.isAntiDotMode {
            TimingSliderRow(model: settings, timing: .silenceThreshold, compact: true)
        }

        SectionLabel(Text(verbatim: SettingsWindowController.Page.fades.title))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 4)
        SettingsSwitchRow(model: settings, kind: .fades, showsSubtitle: false)
            .opacity(settings.playerCanFade ? 1 : 0.45) // a disabled switch alone barely shows it
        if settings.timings.fadesEnabled && settings.playerCanFade {
            TimingSliderRow(model: settings, timing: .fadeOut, compact: true)
            TimingSliderRow(model: settings, timing: .fadeIn, compact: true)
        }

        SectionLabel(Text(verbatim: SettingsWindowController.Page.advanced.title))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 4)
        SettingsSwitchRow(model: settings, kind: .levelsMusic, showsSubtitle: false)
            .opacity(settings.isAntiDotMode ? 0.45 : 1)
        SettingsSwitchRow(model: settings, kind: .staysPausedAfterCalls, showsSubtitle: false)
    }

    /// A small chevron on a pill, centered: down while folded, up while not.
    private var chevron: some View {
        Button { model.perform(.toggleMoreSettings) } label: {
            Image(systemName: model.showsMoreSettings ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.appSecondary)
                .frame(width: 44, height: 16)
                .background(Capsule().fill(.chipFill))
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: model.showsMoreSettings ? Self.hideTitle : Self.showTitle))
        .accessibilityLabel(Text(verbatim: model.showsMoreSettings ? Self.hideTitle : Self.showTitle))
    }

    static var showTitle: String {
        String(localized: "Show More Settings", comment: "Menu: the chevron below Ignored Apps that shows Detection’s, Fades’ and Advanced’s settings (its tooltip and VoiceOver label)")
    }

    static var hideTitle: String {
        String(localized: "Hide More Settings", comment: "Menu: the chevron that folds Detection’s, Fades’ and Advanced’s settings away again (its tooltip and VoiceOver label)")
    }
}
