import AppKit
import SwiftUI
import AutoHushKit

/// The welcome window's second page (P4): what the chosen player needs,
/// each with its state and the way to allow it; Done once nothing's missing.
struct WelcomePermissionsView: View {
    let model: SettingsModel

    var body: some View {
        let name = model.chosenPlayerName ?? ""
        let state = model.permissions
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let player = model.chosenPlayer {
                    Image(nsImage: player.icon(size: 56)).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow AutoHush to Work", comment: "Welcome window: title of the page that asks for the permissions AutoHush needs")
                        .font(.appTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "AutoHush needs these to pause and resume \(name) for you.",
                                comment: "Welcome window, under “Allow AutoHush to Work”; %@ is the music player"))
                        .captionStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    if let control = state.control {
                        row(symbol: "music.note", tint: .controlPermissionTile, title: PermissionText.controlTitle(name),
                            note: PermissionText.controlNote(name, state.controlAccess), access: state.controlAccess) {
                            PermissionButton(model: model, permission: control, access: state.controlAccess)
                        }
                        CardDivider()
                    }
                    row(symbol: "waveform", tint: .audioPermissionTile, title: PermissionText.audioTitle,
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
            HStack(spacing: 8) {
                Button { model.showWelcomePlayers() } label: {
                    Text("Back", comment: "Welcome window: button that goes back to the list of music players")
                }
                .buttonStyle(.chip)
                Spacer()
                Button { model.finishWelcome() } label: {
                    Text("Done", comment: "Welcome window: button that closes it once the permissions are allowed")
                        .font(.appBody.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                // Blue, without Return: AutoHush has no keyboard shortcuts.
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                .disabled(!state.allSatisfied)
            }
        }
        .padding(20)
        .frame(width: 460)
        .font(.appBody)
    }

    private func row<Trailing: View>(symbol: String, tint: AppearanceStyle, title: String, note: String, access: PermissionAccess,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.onColorSymbol)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint))
                .accessibilityHidden(true)
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
