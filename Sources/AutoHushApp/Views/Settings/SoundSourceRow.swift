import AppKit
import SwiftUI
import AutoHushKit

/// An app in Settings → Sound Sources: its icon and name, whether it pauses
/// the music, and its switch; selected, on the accent color with its text
/// white, as macOS's lists (A1a, the user's pick, 2026-11-01: the faint
/// selection looked like the pointer's highlight). A click selects the row anywhere but on the
/// switch, which keeps its own clicks, ⌘ and ⇧ as in macOS's lists; from
/// the keyboard, Return switches the highlighted app on or off and Space
/// adds its row to the selection or takes it out, so several can be
/// removed too (the user, 2026-11-03). The arrow keys (Tab too) and the
/// pointer highlight it, as Settings' other rows. VoiceOver hears it as one,
/// as a `SwitchRow`: the switch, named by the app, its words its hint (VO8,
/// the a11y audit, 2026-11-06).
struct SoundSourceRow: View {
    let model: SettingsModel
    let row: AppListModel.Row
    @FocusState private var rowFocused: Bool
    @FocusState private var switchFocused: Bool
    /// VoiceOver's cursor on the row's control brings the highlight (K5-1).
    @AccessibilityFocusState private var controlHasVoiceOverCursor: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.voiceOver) private var voiceOver

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.image(for: row.source, players: model.playerOptions, size: 24))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                RowTitle(
                    Text(verbatim: row.source.name),
                    subtitle: Text(verbatim: subtitle),
                    isOnSelection: isSelected
                )
                .accessibilityHidden(true) // the switch says it
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let keys = NSEvent.modifierFlags
                list.click(on: row.id, command: keys.contains(.command), shift: keys.contains(.shift))
            }
            Toggle(isOn: isOn) {
                Text(verbatim: row.source.name)
            }
            .toggleStyle(PillToggleStyle())
            .focused($switchFocused)
            .focusEffectDisabled(keyboard != nil)
            .accessibilityHint(Text(verbatim: subtitle))
            .accessibilityFocused($controlHasVoiceOverCursor)
            // A white ground while it's on, so its accent color shows on the
            // selection; off, macOS's own switch on the selection, whose
            // track shows there (D1b, the a11y audit's D1, the user's pick,
            // 2026-11-06: on white, an off switch vanished in dark mode).
            .background { if isSelected, isOn.wrappedValue { Capsule().fill(.onSelection).padding(-2) } }
        }
        .background {
            if isSelected { SelectionFill().padding(.horizontal, -6).padding(.vertical, -4) }
        }
        .contentShape(Rectangle())
        .focusable(interactions: .activate) // as a button: Tab, not a click, gives it focus
        .focused($rowFocused)
        .focusEffectDisabled(keyboard != nil) // the row's tint shows it
        // The arrow keys and the pointer highlight it, its tint as far out as
        // the selection's; Return switches the app on or off, Space adds it
        // to the selection or takes it out.
        .highlightableRow(isFocused: rowFocused || switchFocused, cornerRadius: 6, vertical: 4,
                          press: switchFromKeys,
                          select: { list.toggleSelection(of: row.id) }, voiceOverTarget: $controlHasVoiceOverCursor)
        .onKeyPress(.space) {
            list.toggleSelection(of: row.id)
            return .handled
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Self.removeFromListTitle) { list.removeFromList(row) }
        .contextMenu {
            // The selection, when this row is one of several selected, as in Finder.
            Button { list.removeFromList(row) } label: { Self.removeFromListTitle }
        }
    }

    private var list: AppListModel { model.appList }
    private var isSelected: Bool { list.selectedAppIDs.contains(row.id) }
    /// Under its name: whether it pauses the player, mutes it or is ignored.
    private var subtitle: String { SourceText.subtitle(isIgnored: row.isIgnored, mutes: model.playerMutesNow) }
    /// The switch: on while the app pauses the player, off while it's ignored.
    private var isOn: Binding<Bool> {
        Binding(get: { !row.isIgnored }, set: { model.settings.setIgnored(row.source, !$0) })
    }

    /// Return on the row: the app switched on or off, and VoiceOver told
    /// what it does now, which it doesn't say when the switch changes from
    /// the row (the a11y round 2's leftovers, 2026-11-06).
    private func switchFromKeys() {
        let ignores = !row.isIgnored
        model.settings.setIgnored(row.source, ignores)
        guard voiceOver.isOn() else { return }
        postStepAnnouncement(row.source.name + ", " + SourceText.subtitle(isIgnored: ignores, mutes: model.playerMutesNow))
    }

    private static var removeFromListTitle: Text {
        Text("Remove from List", comment: "Settings → Sound Sources: item of an app's contextual menu that forgets it")
    }
}
