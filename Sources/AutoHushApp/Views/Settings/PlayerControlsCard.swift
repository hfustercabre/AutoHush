import AppKit
import SwiftUI
import AutoHushKit
import CheckedPlayers

/// Settings → Fine-Tuning's first card (F4 + F5, the user's pick,
/// 2026-11-05; Media Player's before, B1), titled with the chosen player's
/// name: "Main control", a pop-up of the controls that can be its main one
/// (`PlayerControls.choices`, the recommended one so named, each with its
/// check's result in words and its mark), the chosen one's note under it as Add an App says it; its
/// one control read only when there's nothing to choose. Then "Use backup
/// controls" and, under it while the panel is a backup, "Use the Now
/// Playing panel while muted" (dimmed, with a note, while the first is off), Details… (its controls
/// in a sheet), and Restore Defaults once one differs. An app added before
/// backup controls were kept: dimmed, with Check Again…; a web app not
/// learned yet: dimmed, with "Controls not learned". No card while no
/// player is chosen, nor for one that's only muted. Media Player's Controls
/// row opens the page scrolled to it (`SettingsModel.showFineTuning`).
struct PlayerControlsCard: View {
    let model: SettingsModel
    @State private var showsDetails = false
    /// Opens the main control's pop-up from the keys.
    @State private var popUp = PopUpOpener()

    var body: some View {
        if let controls = model.chosenControls, let name = model.chosenPlayerName {
            let unavailable = controls.needsCheckAgain || controls.notLearned
            Card(Text(verbatim: name)) {
                Group {
                    if controls.listedChoices.count > 1, !unavailable {
                        mainControlPopUp(controls, player: name)
                    } else {
                        PlainMainControlRow(control: controls.main.kind).unavailable(unavailable)
                    }
                }
                // Where Media Player's Controls row scrolls the page to.
                .background { ScrollAnchor(id: AnyHashable(SettingsCard.playerControls)) }
                if controls.needsCheckAgain {
                    SwitchRow(Text(verbatim: BackupText.uses), isOn: .constant(false)).unavailable(true)
                    NoteLabel(BackupText.checkAgain(name), kind: .info)
                    Button { model.actions?.checkPlayerAgain() } label: { Text(verbatim: ControlErrorFix.checkAgain.title) }
                        .buttonStyle(.chip)
                } else if controls.notLearned {
                    SwitchRow(Text(verbatim: BackupText.uses), isOn: .constant(false)).unavailable(true)
                    NoteLabel(AppStatus.controlsNotLearnedLine, kind: .info)
                } else {
                    SwitchRow(Text(verbatim: BackupText.uses), subtitle: Text(verbatim: BackupText.usesSubtitle),
                              isOn: switchBinding(controls, \.usesBackups), isCurrent: isFocus)
                    if controls.hasPanelBackup {
                        DependentRow {
                            VStack(alignment: .leading, spacing: 4) {
                                SwitchRow(Text(verbatim: BackupText.panelWhileMuted), subtitle: Text(verbatim: BackupText.panelSubtitle),
                                          isOn: switchBinding(controls, \.panelWhileMuted))
                                    .unavailable(!controls.switches.usesBackups)
                                if !controls.switches.usesBackups { NoteLabel(BackupText.off, kind: .info) }
                            }
                        }
                    }
                }
                Button { showsDetails = true } label: { Text(verbatim: BackupText.details) }
                    .buttonStyle(.chip)
            } footer: {
                RestoreDefaultsButton(model: model, card: .playerControls)
            }
            .sheet(isPresented: $showsDetails) {
                ControlDetailsView(player: name, controls: model.chosenControls ?? controls) { showsDetails = false }
            }
        }
    }

    /// "Main control" and its pop-up, as About's update pop-up (borderless,
    /// Return or Space shows the choices, ← and → choose), the chosen
    /// control's note under it. A click anywhere in it shows the choices.
    private func mainControlPopUp(_ controls: PlayerControls, player: String) -> some View {
        // The panel last, apart: it opens on screen for a moment.
        // A control not learned yet among them, dimmed (the user, 2026-11-05).
        let quiet = controls.listedChoices.filter { $0.kind != .panel }
        let panel = controls.listedChoices.first { $0.kind == .panel }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: BackupText.mainControlRow) // a row's title
                    .accessibilityHidden(true) // the pop-up says it, as its label
                Spacer(minLength: 8)
                Picker(selection: Binding(
                    get: { (model.chosenControls ?? controls).main.kind },
                    set: { model.chooseMainControl($0) }
                )) {
                    ForEach(quiet, id: \.kind) { item($0, controls: controls) }
                    if let panel {
                        Divider()
                        item(panel, controls: controls)
                    }
                } label: {
                    Text(verbatim: BackupText.mainControlRow)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .opened(by: popUp)
            }
            ChosenControlNote(control: controls.main, player: player)
        }
        // A click anywhere in the row shows the choices, as one on a switch row turns it.
        .clickAnywhere { popUp.open() }
        .highlightableRow(press: { popUp.open() }, adjust: { step in
            let now = model.chosenControls ?? controls
            // In the order the pop-up shows them: the panel last.
            let shown = now.choices.filter { $0.kind != .panel } + now.choices.filter { $0.kind == .panel }
            if let kind = shown.map(\.kind).stepping(from: now.main.kind, by: step) { model.chooseMainControl(kind) }
        }, isCurrent: isFocus, arrivalSpeech: PopUpOpener.arrivalSpeech(BackupText.mainControlRow) {
            let now = model.chosenControls ?? controls
            return Self.itemTitle(now.main, recommended: now.main.kind == controls.recommended,
                                  notYet: controls.notYetChoices.contains(now.main))
        })
    }

    /// A pop-up item: the control's name with how its check found it, in
    /// words and its mark (`itemTitle`).
    /// One not learned yet ("… (not learned yet)") is dimmed and can't be chosen.
    private func item(_ control: PlayerControls.Control, controls: PlayerControls) -> some View {
        let notYet = controls.notYetChoices.contains(control)
        let title = Self.itemTitle(control, recommended: control.kind == controls.recommended, notYet: notYet)
        return Label {
            Text(verbatim: title)
        } icon: {
            Image(nsImage: Self.markImage(control.found?.mark ?? .notTried))
        }
        .tag(control.kind)
        .selectionDisabled(notYet)
    }

    /// A pop-up item's title: the control's name and, in brackets, how its
    /// check found it ("AppleScript (Recommended, works)", "Its playback
    /// menu (works)"), so VoiceOver reads what its mark shows (VO7b, the
    /// a11y audit's VO7, the user's pick, 2026-11-06: a menu item's image
    /// isn't read, its description neither); one not learned yet, "… (not
    /// learned yet)".
    static func itemTitle(_ control: PlayerControls.Control, recommended: Bool, notYet: Bool) -> String {
        let name = WayText.control(control.kind)
        if notYet { return BackupText.notLearnedYet(name) }
        let result = BackupText.result(control.found?.mark ?? .notTried)
        return recommended ? BackupText.recommended(name, result) : BackupText.found(name, result)
    }

    /// The card's rows stand for what Media Player's Controls row opened:
    /// the highlight goes to the first one that can take it.
    private var isFocus: () -> Bool {
        { [model] in model.fineTuningFocus == .playerControls }
    }

    /// One of its switches, set through AutoHush (an added app's setup keeps it).
    private func switchBinding(_ controls: PlayerControls, _ path: WritableKeyPath<BackupSwitches, Bool>) -> Binding<Bool> {
        Binding(get: { (model.chosenControls ?? controls).switches[keyPath: path] }, set: { value in
            var switches = (model.chosenControls ?? controls).switches
            switches[keyPath: path] = value
            model.actions?.setBackupSwitches(switches)
        })
    }

    /// A check's mark as a pop-up item's image, in `WayRow`'s symbols and
    /// colors: drawn as they are (a menu draws a template image in its
    /// text's color).
    static func markImage(_ mark: CheckResult.Mark) -> NSImage {
        let (symbol, color): (String, NSColor) = switch mark {
        case .works: ("checkmark.circle.fill", .systemGreen)
        case .some: ("exclamationmark.circle.fill", .systemOrange)
        case .none, .notThere: ("xmark.circle.fill", .secondaryLabelColor)
        default: ("minus.circle", .secondaryLabelColor)
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) ?? NSImage()
        image.isTemplate = false
        return image
    }
}

/// "Main control" and its one control, read only: nothing to choose.
private struct PlainMainControlRow: View {
    let control: WayOrder.Kind

    var body: some View {
        HStack {
            Text(verbatim: BackupText.mainControlRow)
            Spacer(minLength: 8)
            Text(verbatim: WayText.control(control)).foregroundStyle(.appSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Under the pop-up: how its check found the chosen control, as Add an App
/// and Details say it (`WayRow`'s note), a caption, or a warning where it
/// doesn't work in every window state; none for one kept before checks
/// tried window states.
private struct ChosenControlNote: View {
    let control: PlayerControls.Control
    let player: String

    var body: some View {
        if let found = control.found {
            // A check with the app's windows closed tried only that state.
            let note = AddAppText.wayNote(found, app: player, windowsClosed: found.states.contains { $0.state == .windowsClosed })
            if found.mark == .some {
                NoteLabel(note, font: .appCaption)
            } else {
                Text(verbatim: note).captionStyle()
            }
        }
    }
}
