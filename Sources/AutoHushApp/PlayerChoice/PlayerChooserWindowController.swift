import AppKit
import SwiftUI

/// What `AppDelegate` needs of the welcome window; tests stand in for it, so
/// they never put a window on screen.
@MainActor
protocol PlayerChooserPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func close()
}

/// The welcome window: asks which music player AutoHush controls. It opens
/// at launch while none is chosen, and again when a supported player opens
/// then. Closing it leaves AutoHush waiting; the menu and Settings can
/// choose too.
@MainActor
final class PlayerChooserWindowController: NSWindowController, PlayerChooserPresenting {
    init(model: SettingsModel) {
        let hosting = NSHostingController(rootView: PlayerChooserView(model: model))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Welcome to AutoHush", comment: "Title of the window that asks for the music player")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if !isVisible { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

/// The music players as rows in a card, like Settings → Apps; the user picks
/// one and continues. Players that aren't installed are dimmed and can't be
/// picked. When only one is installed, it starts picked.
struct PlayerChooserView: View {
    let model: SettingsModel
    /// The player the user clicked.
    @State private var clicked: String?

    /// The clicked player or, until one is, the only installed one.
    private var picked: String? {
        clicked ?? model.playerOptions.onlyInstalled?.bundleID
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Choose Your Music Player")
                .font(.appTitle)
            Text("AutoHush pauses it while other apps play audio, and resumes it afterwards. You can change it at any time in the menu or in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Card {
                ForEach(Array(model.playerOptions.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { CardDivider() }
                    row(for: option)
                }
            }
            if model.playerOptions.noneInstalled {
                NoteLabel(PlayerOption.noneInstalledWarning)
            } else if let note = PlayerOption.onlyInstalledNote(among: model.playerOptions) {
                NoteLabel(note, kind: .info)
            }
            Button {
                if let picked { model.chooseMusicPlayer(picked) }
            } label: {
                Text("Continue")
                    .font(.appBody.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            // Blue, without Return: AutoHush has no keyboard shortcuts.
            .buttonStyle(ChipButtonStyle(filled: true, isSelected: true))
            .disabled(!canContinue)
        }
        .padding(24)
        .frame(width: 420)
        .font(.appBody)
    }

    /// A player is picked, and is still installed.
    private var canContinue: Bool {
        model.playerOptions.contains { $0.bundleID == picked && $0.isInstalled }
    }

    /// The player's icon and name, "Not installed" under one that isn't, and
    /// a check on the picked one.
    private func row(for option: PlayerOption) -> some View {
        let isPicked = option.bundleID == picked
        return Button {
            clicked = option.bundleID
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: option.icon(size: 32))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                RowTitle(Text(verbatim: option.name),
                         subtitle: option.isInstalled ? nil : Text(PlayerOption.notInstalledLabel))
                Spacer(minLength: 8)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isPicked ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                                     isPicked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .buttonStyle(ChipButtonStyle()) // which dims it while disabled
        .padding(.horizontal, -6)
        .disabled(!option.isInstalled)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
