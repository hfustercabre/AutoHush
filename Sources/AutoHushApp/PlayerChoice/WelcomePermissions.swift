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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WindowHeader(icon: model.chosenPlayer?.icon(size: 56),
                             description: Text(String(localized: "AutoHush needs these to pause and resume \(name) for you.",
                                                      comment: "Welcome window, at the top of the page titled “Allow AutoHush to Work”, beside the media player's icon; %@ is the media player")))
                SectionHeading(Text("Permissions", comment: "Settings → Diagnostics and the welcome window: the heading over the permissions AutoHush needs"))
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
                        if !state.audio.isSatisfied {
                            HStack {
                                Spacer()
                                Button { model.useAntiDotMode() } label: { Text(verbatim: PermissionText.useAntiDot) }
                                    .buttonStyle(.chip)
                            }
                        }
                    }
                }
            }
            .windowMargins()
            BottomBar(margin: HostedWindowController.margin) {
                Button { model.showWelcomePlayers() } label: {
                    Text("Back", comment: "Welcome window: button that goes back to the list of media players")
                }
                .buttonStyle(.chip)
                Spacer()
                Button { model.finishWelcome() } label: {
                    Text("Done", comment: "Welcome window: button that closes it once the permissions are allowed")
                        .font(.appBody.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!state.allSatisfied)
            }
        }
        .frame(width: PlayerChooserView.width)
        .font(.appBody)
    }

    private func row<Trailing: View>(symbol: String, title: String, note: String, access: PermissionAccess,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: symbol)
            RowTitle(Text(verbatim: title), subtitle: Text(verbatim: note))
            Spacer(minLength: 8)
            switch access {
            case .allowed:
                Label {
                    Text("Allowed", comment: "Diagnostics and the welcome window: a permission that is granted")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.appCallout)
                .foregroundStyle(.appSuccess)
            case .notNeeded:
                Text("Not Needed", comment: "Welcome window: Audio Recording while AntiDot mode is on, which doesn't use it")
                    .font(.appCallout)
                    .foregroundStyle(.appSecondary)
            default:
                trailing()
            }
        }
        .accessibilityElement(children: .contain)
    }
}
