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
final class PlayerChooserWindowController: HostedWindowController, PlayerChooserPresenting {
    init(model: SettingsModel) {
        super.init(content: Self.sizedToFit(PlayerChooserView(model: model)),
                   title: String(localized: "Welcome to AutoHush", comment: "Title of the window that asks for the music player"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The music players as rows in a card, like Settings → Apps, then the
/// Safari web apps in a card of their own, and "Add a Web App…"; the user
/// picks one and continues.
/// Players that aren't installed come after the installed apps, dimmed, and
/// can't be picked. When only one is installed, it starts picked. From
/// `PlayerOption.searchThreshold` players on, a search narrows them down and
/// the list scrolls at a fixed height.
struct PlayerChooserView: View {
    let model: SettingsModel
    /// The player the user clicked.
    @State private var clicked: String?
    @State private var search = ""

    /// The players' list's height while it scrolls: about six rows.
    static let scrollingListHeight: CGFloat = 340

    /// The clicked player or, until one is, the only installed one.
    private var picked: String? {
        clicked ?? model.playerOptions.onlyInstalled?.bundleID
    }

    var body: some View {
        if model.welcomeAsksPermissions {
            WelcomePermissionsView(model: model)
        } else {
            playersPage
        }
    }

    /// The first page: the players to choose from.
    private var playersPage: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Choose Your Music Player", comment: "Welcome window: its title")
                .font(.appTitle)
            Text("AutoHush pauses it while other apps play audio, and resumes it afterwards. You can change it at any time in the menu or in Settings.",
                 comment: "Welcome window, under its title")
                .multilineTextAlignment(.center)
                .foregroundStyle(.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.playerOptions.isSearchable {
                SearchField(text: $search)
                ScrollView {
                    groups(model.playerOptions.offered.matching(search))
                }
                .frame(height: Self.scrollingListHeight)
            } else {
                groups(model.playerOptions.offered)
            }
            if model.playerOptions.noneInstalled {
                NoteLabel(PlayerOption.noneInstalledWarning)
            } else if let note = PlayerOption.onlyInstalledNote(among: model.playerOptions) {
                NoteLabel(note, kind: .info)
            }
            Button {
                if let picked { model.chooseMusicPlayer(picked) }
            } label: {
                Text("Continue", comment: "Button in the welcome window and the Add a Web App window: goes on with what's chosen or typed")
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

    /// The apps' card, then the web apps' under their heading. A card shows
    /// only when it has a player, or when neither has (with the search's note).
    @ViewBuilder private func groups(_ options: [PlayerOption]) -> some View {
        let start = options.webAppsStart ?? options.count
        let apps = Array(options[..<start])
        let webApps = Array(options[start...])
        VStack(alignment: .leading, spacing: 8) {
            if !apps.isEmpty || webApps.isEmpty {
                Card { players(apps) }
            }
            if !webApps.isEmpty {
                WebAppsHeading()
                    .padding(.leading, 4) // as a SectionHeading
                    .padding(.top, apps.isEmpty ? 0 : 6)
                Card { players(webApps) }
            }
            Button { model.addWebApp() } label: {
                Label { Text(verbatim: PlayerOption.addWebAppTitle) } icon: { Image(systemName: "plus.circle") }
            }
            .buttonStyle(.chip)
        }
    }

    /// The players' rows, for a card; a note when the search matched none.
    @ViewBuilder private func players(_ options: [PlayerOption]) -> some View {
        if options.isEmpty {
            Text(verbatim: PlayerOption.noMatchNote(search))
                .foregroundStyle(.appSecondary)
        }
        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
            if index > 0 { CardDivider() }
            row(for: option)
        }
    }

    /// A player is picked, and is still installed.
    private var canContinue: Bool {
        model.playerOptions.contains { $0.bundleID == picked && $0.isInstalled }
    }

    /// The player's icon and name, "Not installed" under one that isn't, and
    /// a check on the picked one. A suggested web app isn't picked: a click
    /// opens "Add a Web App" filled in.
    private func row(for option: PlayerOption) -> some View {
        let isPicked = option.bundleID == picked
        return Button {
            if option.webAddress != nil {
                model.chooseMusicPlayer(option.bundleID)
            } else {
                clicked = option.bundleID
            }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: option.icon(size: 32))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                RowTitle(Text(verbatim: option.name),
                         subtitle: option.isInstalled ? nil : Text(PlayerOption.notInstalledLabel),
                         badge: option.isUntested ? PlayerOption.untestedBadge : nil)
                Spacer(minLength: 8)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isPicked ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary),
                                     isPicked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .opacity(option.webAddress == nil ? 1 : 0) // a suggestion isn't picked
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .buttonStyle(ChipButtonStyle()) // which dims it while disabled
        .padding(.horizontal, -6)
        .disabled(!option.isClickable)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
