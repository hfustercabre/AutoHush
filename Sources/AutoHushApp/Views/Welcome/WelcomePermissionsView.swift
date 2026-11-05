import AppKit
import SwiftUI
import AutoHushKit

/// The welcome window's second page (P4): what the chosen player needs,
/// each with its state and the way to allow it; Done once nothing's missing.
/// Its title is in the title bar (`PlayerChooserWindowController`).
struct WelcomePermissionsView: View {
    let model: SettingsModel

    var body: some View {
        let name = model.chosenPlayerName ?? ""
        let state = model.permissions
        WindowPage(icon: model.chosenPlayer?.icon(size: 56),
                   description: Text(String(localized: "AutoHush needs these to pause and resume \(name) for you.",
                                            comment: "Welcome window, at the top of the page titled “Allow AutoHush to Work”, beside the media player's icon; %@ is the media player")),
                   width: PlayerChooserView.width) {
            SectionHeading(Text(verbatim: PermissionText.heading))
                .padding(.top, 8)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if let control = state.control {
                        row(symbol: "music.note", title: PermissionText.controlTitle(name),
                            note: PermissionText.controlNote(name, state.controlAccess), access: state.controlAccess) {
                            PermissionButton(model: model, permission: control, access: state.controlAccess)
                        }
                        CardDivider()
                    }
                    row(symbol: "waveform", title: PermissionText.audioTitle,
                        note: PermissionText.audioNote(state.audio), access: state.audio) {
                        PermissionButton(model: model, permission: .systemAudioRecording, access: state.audio)
                    }
                    // Not for a player that can only be muted: AntiDot mode can't mute it.
                    if !state.audio.isSatisfied, model.antiDotUnavailableFor == nil {
                        // What it trades, beside it (F2a, 2026-11-02); VoiceOver
                        // hears it once, as the chip's hint.
                        HStack {
                            Text(verbatim: PermissionText.antiDotTradeOff)
                                .captionStyle()
                                .accessibilityHidden(true)
                            Spacer()
                            Button { model.useAntiDotMode() } label: { Text(verbatim: PermissionText.useAntiDot) }
                                .buttonStyle(.chip)
                                .help(PermissionText.antiDotTradeOff)
                                .accessibilityHint(Text(verbatim: PermissionText.antiDotTradeOff))
                        }
                    }
                }
            }
        } bar: {
            Button { model.showWelcomePlayers() } label: {
                Text(verbatim: ButtonText.back)
            }
            .buttonStyle(.chip)
            Spacer()
            WelcomeMenuBarNote()
            MainButton(Self.doneTitle) { model.actions?.finishWelcome() }
                .disabled(!state.allSatisfied)
        }
        // Allowed in System Settings, a row's button goes away: VoiceOver
        // hears what was allowed, and when Done can be clicked (A6, 2026-11-01).
        .onChange(of: model.permissions) { old, new in
            if let announcement = Self.announcement(from: old, to: new) { postStepAnnouncement(announcement) }
        }
    }

    private static var doneTitle: String {
        ButtonText.done
    }

    /// What VoiceOver hears as the permissions go from `old` to `new`: each
    /// one that turned allowed, then, once nothing's missing, that Done can
    /// be clicked; `nil` when neither happened. A read for another player
    /// (the one chosen as the page opens) says nothing about this one.
    static func announcement(from old: PermissionsState, to new: PermissionsState) -> String? {
        guard old.player == new.player else { return nil }
        var parts: [String] = []
        if let control = new.control, new.controlAccess == .allowed, old.controlAccess != .allowed {
            parts.append(control.allowedTitle)
        }
        if new.audio == .allowed, old.audio != .allowed {
            parts.append(Permission.systemAudioRecording.allowedTitle)
        }
        if new.allSatisfied, !old.allSatisfied {
            parts.append(String(localized: "Done is available",
                                comment: "Welcome window, said by VoiceOver once every permission is allowed (or not needed): the Done button can be clicked now"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    private func row<Trailing: View>(symbol: String, title: String, note: String, access: PermissionAccess,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        PermissionRow(symbol: symbol, title: title, note: note, isAllowed: access == .allowed) {
            if access == .notNeeded {
                Text("Not needed", comment: "Welcome window: Audio Recording while AntiDot mode is on, which doesn't use it")
                    .font(.appCallout)
                    .foregroundStyle(.appSecondary)
            } else {
                trailing()
            }
        }
    }
}
