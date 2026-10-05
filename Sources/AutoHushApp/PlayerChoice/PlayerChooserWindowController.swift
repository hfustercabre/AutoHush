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

/// One tile per music player; the user picks one and continues. Players that
/// aren't installed are dimmed and can't be picked. When only one is
/// installed, it starts picked.
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
                .font(.title2.bold())
            Text("AutoHush pauses it while other apps play audio, and resumes it afterwards. You can change it at any time in the menu or in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.playerOptions) { tile(for: $0) }
            }
            if model.playerOptions.noneInstalled {
                NoteLabel(PlayerOption.noneInstalledWarning)
            } else if let note = PlayerOption.onlyInstalledNote(among: model.playerOptions) {
                NoteLabel(note, kind: .info)
            }
            Button("Continue") {
                if let picked { model.chooseMusicPlayer(picked) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
        }
        .padding(24)
        .frame(width: 420)
    }

    /// Up to three tiles a row, centered, so a lone player isn't off to one side.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(112), spacing: 12), count: min(max(model.playerOptions.count, 1), 3))
    }

    /// A player is picked, and is still installed.
    private var canContinue: Bool {
        model.playerOptions.contains { $0.bundleID == picked && $0.isInstalled }
    }

    private func tile(for option: PlayerOption) -> some View {
        let isPicked = option.bundleID == picked
        return Button {
            clicked = option.bundleID
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: option.icon(size: 64))
                Text(option.name)
                    .lineLimit(1)
                // On every tile, so they're all the same height.
                Text(PlayerOption.notInstalledLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(option.isInstalled ? 0 : 1)
                    .accessibilityHidden(option.isInstalled)
            }
            .padding(10)
            .frame(width: 112)
            .background(RoundedRectangle(cornerRadius: 10).fill(isPicked ? Color.accentColor.opacity(0.15) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isPicked ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isPicked ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!option.isInstalled)
        .opacity(option.isInstalled ? 1 : 0.5)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
