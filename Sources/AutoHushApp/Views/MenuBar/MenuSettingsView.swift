import AppKit
import SwiftUI
import AutoHushKit

/// The menu's settings, below Ignored Apps, each part between lines (the
/// user, 2026-10-17: no cards) under its page's title (2026-10-18):
/// Detection's, Fades' and Advanced's switches, each with its symbol (in
/// the accent color while it's on) and what it does in a few words. A part
/// with more than its switches has a title that unfolds the rest in its
/// place, a chevron at its right (T1, the user's pick, 2026-10-18): AntiDot
/// mode's ways under it ("Modes") and Detection's timings ("Timing"); the
/// fades' lengths under Fade playback. Advanced has nothing more. As in
/// Settings, what doesn't apply is greyed out, never hidden, saying why.
struct MenuSettingsView: View {
    let model: StatusMenuModel
    let settings: SettingsModel

    private func isOpen(_ part: MenuSettingsPart) -> Bool { model.unfoldedSettings.contains(part) }
    /// Shown as open: unfolded and not fading out to fold (its chevron turns at once).
    private func showsOpen(_ part: MenuSettingsPart) -> Bool { isOpen(part) && !model.foldingSettings.contains(part) }
    /// A part's other settings, faded out while it folds.
    private func fading(_ part: MenuSettingsPart) -> Double { model.foldingSettings.contains(part) ? 0 : 1 }
    /// Fading out to fold: the keys and the pointer skip them meanwhile.
    private func isFolding(_ part: MenuSettingsPart) -> Bool { model.foldingSettings.contains(part) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageName(.detection, folding: .detection)
            if isOpen(.detection) {
                innerTitle(Text("Modes", comment: "Settings → Detection and the menu: heading over AntiDot mode"))
                    .opacity(fading(.detection))
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
                    // ← and → choose, while the arrow keys' highlight is on it.
                    .modifier(Highlightable(adjust: { step in
                        let methods: [DetectionMethod] = [.playbackSignals, .openStreams]
                        guard let index = methods.firstIndex(of: settings.detectionMethod) else { return }
                        settings.setDetectionMethod(methods[min(max(index + step, 0), methods.count - 1)])
                    }))
                    .unavailable(!settings.isAntiDotMode)
                    .disabled(isFolding(.detection))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .opacity(fading(.detection))
                    .transition(Self.unfolding)
                }
            }
            if isOpen(.detection) {
                innerTitle(Text("Timing", comment: "Settings → Detection: heading of how long other apps must play or be quiet before your player pauses or resumes"))
                    .opacity(fading(.detection))
                part {
                    slider(.pauseAfter)
                    slider(.resumeAfter)
                    slider(.silenceThreshold).unavailable(settings.isAntiDotMode)
                }
                .disabled(isFolding(.detection))
                .opacity(fading(.detection))
                .transition(Self.unfolding) // the part comes in whole, not its rows
            }
            line
            pageName(.fades, folding: .fades)
            part {
                switchRow(.fades)
                if isOpen(.fades) {
                    Group {
                        slider(.fadeOut)
                        slider(.fadeIn)
                    }
                    .unavailable(!settings.playerCanFade || !settings.timings.fadesEnabled)
                    .disabled(isFolding(.fades))
                    .opacity(fading(.fades))
                }
            }
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
            .padding(.vertical, MenuSpacing.partVertical)
    }

    /// The line between the parts, as between the menu's own parts.
    private var line: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, MenuSpacing.lineVertical)
            .transition(.opacity)
    }

    /// One of the switches: its symbol, its name and what it does, and the
    /// switch; dimmed while it can't be changed, with why on a line of its
    /// own under it, undimmed (R2, the user's pick, 2026-10-18), and in its
    /// tooltip and VoiceOver hint.
    private func switchRow(_ kind: SettingsSwitch) -> some View {
        MenuSwitchLine(kind: kind, settings: settings)
    }

    private func slider(_ timing: SettingsTiming) -> some View {
        TimingSliderRow(model: settings, timing: timing, compact: true)
            .padding(.horizontal, 10)
            .padding(.vertical, MenuSpacing.sliderVertical)
            .transition(Self.unfolding)
    }

    /// A Settings page's name over its part; for a part with more settings
    /// than its switches (`folding`), the whole line is the button that
    /// unfolds them, a plain chevron at its right (T1, the user's pick,
    /// 2026-10-18), tinted as the menu's controls under the pointer.
    @ViewBuilder private func pageName(_ page: SettingsWindowController.Page, folding part: MenuSettingsPart? = nil) -> some View {
        if let part {
            foldingTitle(page, part: part)
                .transition(.opacity)
        } else {
            MenuPartTitle(Text(verbatim: page.title))
                .transition(.opacity)
        }
    }

    /// The folding part's title: down while its other settings are folded,
    /// up while they show.
    private func foldingTitle(_ page: SettingsWindowController.Page, part: MenuSettingsPart) -> some View {
        let toggle = { model.perform(.toggleSettings(part)) }
        return Button(action: toggle) {
            HStack(spacing: 5) {
                SectionLabel(Text(verbatim: page.title))
                Spacer(minLength: 0)
                Image(systemName: showsOpen(part) ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HighlightableControl(cornerRadius: 6, inset: 8, press: toggle))
        // Its tint's 3 pt above and under the title, out of the layout: the
        // rows under it as close as under the other titles.
        .padding(.top, MenuSpacing.titleTop - 3)
        .padding(.bottom, MenuSpacing.titleBottom - 3)
        .help(Text(verbatim: showsOpen(part) ? Self.hideTitle : Self.showTitle))
        .accessibilityLabel(Text(verbatim: page.title))
        .accessibilityValue(showsOpen(part) ? AccessibilityText.expanded : AccessibilityText.collapsed)
        .accessibilityAddTraits(.isHeader)
    }

    /// A title inside a page's part ("Modes", "Timing"): a description's size, grey.
    private func innerTitle(_ title: Text) -> some View {
        MenuInnerTitle(title)
            .padding(.horizontal, 14)
            .padding(.top, MenuSpacing.innerTitleTop)
            .transition(Self.unfolding)
    }

    /// How the rows a part unfolds come in: once the rows under them have
    /// moved and the menu has grown, so none overlap meanwhile (the user,
    /// 2026-10-18: "Make the new rows fade in after the others move"); they
    /// fade out before the part folds (`foldingSettings`). At once with Reduce
    /// Motion.
    static var unfolding: AnyTransition {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return .identity }
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.15).delay(MenuPanel.resizeDuration)),
                           removal: .opacity)
    }

    static var showTitle: String {
        String(localized: "Show More Settings", comment: "Menu: the tooltip of Detection’s or Fades’ title, which shows the rest of that part’s settings")
    }

    static var hideTitle: String {
        String(localized: "Hide More Settings", comment: "Menu: the tooltip of Detection’s or Fades’ title, which folds the rest of that part’s settings away again")
    }
}

/// Why a switch is dimmed, as its row's tooltip; none while it isn't.
private struct ReasonTooltip: ViewModifier {
    let reason: String?

    func body(content: Content) -> some View {
        if let reason { content.help(Text(verbatim: reason)) } else { content }
    }
}

/// One of the menu's settings switches, as `MenuSettingsView` lists them;
/// the arrow keys and the pointer highlight it, and its switch takes the
/// keyboard's focus (F5), unless it can't be changed.
private struct MenuSwitchLine: View {
    let kind: SettingsSwitch
    let settings: SettingsModel
    @FocusState private var isFocused: Bool

    var body: some View {
        let isOn = kind.isOn(settings)
        let reason = kind.unavailableReason(settings)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MenuSpacing.row.gap) {
                Image(systemName: kind.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.appSecondary))
                    .frame(width: MenuSpacing.row.picture)
                    .accessibilityHidden(true)
                RowTitle(kind.title, subtitle: kind.shortExplanation)
                    .accessibilityHidden(true) // the switch says it: one stop for VoiceOver
                Spacer(minLength: 8)
                Toggle(isOn: Binding(get: { kind.isOn(settings) }, set: { kind.set($0, in: settings) })) { kind.title }
                    .toggleStyle(PillToggleStyle())
                    .controlSize(MenuSpacing.switchSize)
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .accessibilityHint(reason.map { Text(verbatim: $0) } ?? kind.shortExplanation)
            }
            .unavailable(kind.isUnavailable(settings))
            if let reason {
                Label(reason, systemImage: "info.circle")
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, MenuSpacing.row.picture + MenuSpacing.row.gap)
                    .accessibilityHidden(true) // the switch's hint says it
            }
        }
        .padding(.leading, MenuSpacing.row.leading - 8) // the part's own 8 pt inside
        .padding(.trailing, 8)
        .padding(.vertical, MenuSpacing.rowVertical)
        .modifier(Highlightable(isFocused: isFocused, isAvailable: !kind.isUnavailable(settings),
                                press: { kind.set(!kind.isOn(settings), in: settings) }))
        .modifier(ReasonTooltip(reason: reason))
    }
}
