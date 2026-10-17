import SwiftUI
import AutoHushKit

/// The rows of the menu's settings, below Ignored Apps: Settings →
/// Detection's, → Fades' and → Advanced's switches, always shown (the user,
/// 2026-10-17), and the pages' names, their timings and AntiDot mode's ways,
/// shown only while unfolded, above a small chevron on a pill (C3). As in Settings, only
/// what applies shows: the fades' lengths while they're on, AntiDot mode's
/// ways while it's on, the silence threshold while it's off.
enum MoreSettingsRow: String, CaseIterable {
    case detectionHeading, antiDot, antiDotWays, pauseAfter, resumeAfter, silenceThreshold
    case fadesHeading, fades, fadeOut, fadeIn
    case advancedHeading, levelsMusic, staysPausedAfterCalls
    /// Shows or folds the others; always shown.
    case chevron

    /// A switch (or the chevron): shown folded too.
    var isSwitch: Bool {
        [.antiDot, .fades, .levelsMusic, .staysPausedAfterCalls, .chevron].contains(self)
    }

    /// Whether it shows, More Settings unfolded.
    @MainActor func applies(_ settings: SettingsModel) -> Bool {
        switch self {
        case .antiDotWays: settings.isAntiDotMode
        case .silenceThreshold: !settings.isAntiDotMode
        case .fadeOut, .fadeIn: settings.timings.fadesEnabled && settings.playerCanFade
        default: true
        }
    }
}

/// One of `MoreSettingsRow`, as wide as the menu.
struct MoreSettingsRowView: View {
    let row: MoreSettingsRow
    let model: StatusMenuModel
    let settings: SettingsModel

    var body: some View {
        content
            // Arriving, it fades in and drifts down into place; going, the reverse.
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived ? 0 : -8)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: arrived)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(width: menuContentWidth, alignment: .leading)
    }

    private var arrived: Bool { model.moreSettingsArrived.contains(row) }

    @ViewBuilder private var content: some View {
        switch row {
        case .detectionHeading: heading(.detection)
        case .antiDot: SettingsSwitchRow(model: settings, kind: .antiDot, showsSubtitle: false)
        case .antiDotWays:
            ChoiceChips(
                options: [DetectionMethod.playbackSignals, .openStreams].map { .init(title: $0.title, value: $0) },
                selection: settings.detectionMethod,
                onSelect: { settings.setDetectionMethod($0) }
            )
        case .pauseAfter: TimingSliderRow(model: settings, timing: .pauseAfter, compact: true)
        case .resumeAfter: TimingSliderRow(model: settings, timing: .resumeAfter, compact: true)
        case .silenceThreshold: TimingSliderRow(model: settings, timing: .silenceThreshold, compact: true)
        case .fadesHeading: heading(.fades)
        case .fades:
            SettingsSwitchRow(model: settings, kind: .fades, showsSubtitle: false)
                .opacity(settings.playerCanFade ? 1 : 0.45) // a disabled switch alone barely shows it
        case .fadeOut: TimingSliderRow(model: settings, timing: .fadeOut, compact: true)
        case .fadeIn: TimingSliderRow(model: settings, timing: .fadeIn, compact: true)
        case .advancedHeading: heading(.advanced)
        case .levelsMusic:
            SettingsSwitchRow(model: settings, kind: .levelsMusic, showsSubtitle: false)
                .opacity(settings.isAntiDotMode ? 0.45 : 1)
        case .staysPausedAfterCalls:
            SettingsSwitchRow(model: settings, kind: .staysPausedAfterCalls, showsSubtitle: false)
        case .chevron:
            chevron
                // The rows that apply follow the settings while the menu shows.
                .onChange(of: layout) { model.perform(.updateMoreSettings) }
        }
    }

    /// A page's name, over its rows (unfolded only).
    private func heading(_ page: SettingsWindowController.Page) -> some View {
        SectionLabel(Text(verbatim: page.title))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, page == .detection ? 0 : 4)
    }

    /// What decides which rows show.
    private var layout: [Bool] {
        [settings.isAntiDotMode, settings.timings.fadesEnabled, settings.playerCanFade]
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
