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
                        HStack {
                            Spacer()
                            Button { model.useAntiDotMode() } label: { Text(verbatim: PermissionText.useAntiDot) }
                                .buttonStyle(.chip)
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
            MainButton(Self.doneTitle) { model.actions?.finishWelcome() }
                .disabled(!state.allSatisfied)
        }
    }

    private static var doneTitle: String {
        String(localized: "Done", comment: "Welcome window: button that closes it once the permissions are allowed")
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
