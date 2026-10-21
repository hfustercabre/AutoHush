import AppKit
import SwiftUI
import AutoHushKit

/// The menu's settings, below Ignored Apps, each part between lines (the
/// user, 2026-10-17: no cards) under its page's title (2026-10-18):
/// Detection's, Fades', Calls' and Advanced's switches, each with its symbol (in
/// the accent color while it's on) and what it does in a few words. A part
/// with more than its switches has a title that unfolds the rest in its
/// place, a chevron in the middle of its line (T1, 2026-10-18; centered
/// 2026-10-21): AntiDot mode's ways under it ("Modes") and Detection's
/// timings ("Timing"); the
/// fades' lengths under Fade playback; Level the volume's limits under it,
/// under "Volume".
/// Calls has nothing more. As in
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
                innerTitle(DetectionSettingsView.modesTitle)
                    .opacity(fading(.detection))
            }
            part {
                switchRow(.antiDot)
                if isOpen(.detection) {
                    ChoiceChips(
                        label: DetectionSettingsView.detectByTitle,
                        options: DetectionMethod.antiDotWays.map { .init(title: $0.title, value: $0) },
                        selection: settings.detectionMethod,
                        onSelect: { settings.setDetectionMethod($0) }
                    )
                    .controlSize(.small) // C2: both words fit
                    // ← and → choose, while the arrow keys' highlight is on it.
                    .modifier(Highlightable(adjust: { step in
                        if let method = DetectionMethod.antiDotWays.stepping(from: settings.detectionMethod, by: step) {
                            settings.setDetectionMethod(method)
                        }
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
                innerTitle(DetectionSettingsView.outputTitle)
                    .opacity(fading(.detection))
            }
            part {
                switchRow(.pausesOnDisconnect)
            }
            if isOpen(.detection) {
                innerTitle(DetectionSettingsView.timingTitle)
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
            pageName(.calls)
            part {
                switchRow(.pausesForMicrophone)
                switchRow(.staysPausedAfterCalls)
            }
            line
            pageName(.advanced, folding: .advanced)
            if isOpen(.advanced) {
                innerTitle(AdvancedSettingsView.volumeTitle)
                    .opacity(fading(.advanced))
            }
            part {
                switchRow(.levelsMusic)
                if isOpen(.advanced) {
                    Group {
                        slider(.levelingMaxCut)
                        slider(.levelingMinCut)
                    }
                    .unavailable(!settings.timings.levelsMusic || settings.isAntiDotMode)
                    .disabled(isFolding(.advanced))
                    .opacity(fading(.advanced))
                }
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
        MenuLine().transition(.opacity)
    }

    /// One of the switches: its symbol, its name and what it does, and the
    /// switch; dimmed while it can't be changed, with why on a line of its
    /// own under it, undimmed (R2, the user's pick, 2026-10-18), and in its
    /// tooltip and VoiceOver hint.
    private func switchRow(_ kind: SettingsSwitch) -> some View {
        let reason = kind.unavailableReason(settings)
        return MenuSwitchRow(isOn: Binding(get: { kind.isOn(settings) }, set: { kind.set($0, in: settings) }),
                             label: kind.title, hint: reason.map { Text(verbatim: $0) } ?? kind.shortExplanation,
                             isUnavailable: kind.isUnavailable(settings), reason: reason,
                             // Its tint over the part's own 8 pt inside, and its rows' room above and below.
                             outset: CGSize(width: 8, height: MenuSpacing.rowVertical)) {
            MenuRowSymbol(kind.symbol, isOn: kind.isOn(settings))
        } title: {
            RowTitle(kind.title, subtitle: kind.shortExplanation)
        }
        .padding(.leading, MenuSpacing.row.leading - 8) // the part's own 8 pt inside
        .padding(.trailing, 8)
        .padding(.vertical, MenuSpacing.rowVertical)
        .modifier(ReasonTooltip(reason: reason))
    }

    private func slider(_ timing: SettingsTiming) -> some View {
        TimingSliderRow(model: settings, timing: timing, compact: true)
            .padding(.horizontal, 10)
            .padding(.vertical, MenuSpacing.sliderVertical)
            .transition(Self.unfolding)
    }

    /// A Settings page's name over its part; for a part with more settings
    /// than its switches (`folding`), the whole line is the button that
    /// unfolds them, a plain chevron in the middle of it (T1, the user's
    /// pick, 2026-10-18; centered 2026-10-21), tinted as the menu's
    /// controls under the pointer.
    @ViewBuilder private func pageName(_ page: SettingsWindowController.Page, folding part: MenuSettingsPart? = nil) -> some View {
        if let part {
            foldingTitle(page, part: part)
                .transition(.opacity)
        } else {
            MenuPartTitle(Text(verbatim: page.title))
                .transition(.opacity)
        }
    }

    /// The folding part's title, its chevron in the middle of the line (the
    /// user, 2026-10-21; the titles never reach it: 15 characters at most,
    /// in German): down while its other settings are folded, up while they
    /// show.
    private func foldingTitle(_ page: SettingsWindowController.Page, part: MenuSettingsPart) -> some View {
        let toggle = { model.perform(.toggleSettings(part)) }
        return Button(action: toggle) {
            ZStack {
                SectionLabel(Text(verbatim: page.title))
                    .frame(maxWidth: .infinity, alignment: .leading)
                // As big as the side rows' chevron (C3, the user's pick, 2026-10-21).
                Image(systemName: showsOpen(part) ? "chevron.up" : "chevron.down")
                    .font(.body.weight(.semibold))
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
