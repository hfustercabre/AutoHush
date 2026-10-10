import AppKit
import SwiftUI

/// What `AppDelegate` needs of the welcome window; tests stand in for it, so
/// they never put a window on screen.
@MainActor
protocol PlayerChooserPresenting: AnyObject {
    var isOpen: Bool { get }
    func show()
    func bringForward()
    func close()
}

/// The welcome window: asks which media player AutoHush controls, then for
/// the permissions it needs. It opens at launch while none is chosen, and
/// again when a supported player opens then. Closing it leaves AutoHush
/// waiting; the menu and Settings can choose too. Its title is its page's.
@MainActor
final class PlayerChooserWindowController: HostedWindowController, PlayerChooserPresenting {
    /// `tallestPage`: as for `PlayerChooserView`, else the screen's.
    init(model: SettingsModel, tallestPage: CGFloat? = nil) {
        let view = PlayerChooserView(model: model, tallestPage: tallestPage ?? PlayerChooserView.tallestOnScreen)
        super.init(content: Self.sizedToFit(view), title: Self.title(asksPermissions: model.welcomeAsksPermissions))
        followTitle { Self.title(asksPermissions: model.welcomeAsksPermissions) }
    }

    /// The page's title, in the title bar.
    static func title(asksPermissions: Bool) -> String {
        asksPermissions
            ? String(localized: "Allow AutoHush to Work",
                     comment: "Welcome window: the title (in its title bar) of the page that asks for the permissions AutoHush needs")
            : String(localized: "Choose Your Media Player", comment: "Welcome window: its title, in its title bar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The media players as tiles, as in Settings → General (`PlayerTiles`): the
/// apps, then the Safari web apps and the tile that adds one; the user picks
/// one and continues.
/// Players that aren't installed come after the installed apps, dimmed, and
/// can't be picked. When only one is installed, it starts picked. Past
/// `visibleTileRows` rows of tiles, they scroll. From
/// `PlayerOption.searchThreshold` players on, a search narrows them down.
struct PlayerChooserView: View {
    let model: SettingsModel
    /// The tallest the first page may be: past it, its list scrolls. `nil`:
    /// as tall as the players make it.
    var tallestPage: CGFloat?
    /// The player the user clicked.
    @State private var clicked: String?
    @State private var search = ""

    /// Rows of tiles shown at most, apps and web apps together: past them,
    /// the tiles scroll.
    static let visibleTileRows = 5
    /// Both pages' width, so the window keeps it from one to the other.
    static let width: CGFloat = 540

    /// The tallest the first page may be on the screen it opens on: the
    /// screen's height without the menu bar and the Dock, less the window's
    /// title bar and a margin above and below.
    static var tallestOnScreen: CGFloat? {
        guard let screen = NSScreen.main else { return nil }
        return screen.visibleFrame.height - HostedWindowController.titleBarHeight - 2 * 20
    }

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
        HeightLimit(limit: tallestPage) { playersPageContent }
            .font(.appBody)
    }

    private var playersPageContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                WindowHeader(icon: NSApplication.shared.applicationIconImage,
                             description: Text("AutoHush pauses what's playing on it (music, podcasts or videos) while other apps play audio, and resumes it afterwards. You can change it at any time in the menu or in Settings.",
                                               comment: "Welcome window, at its top beside AutoHush's icon, under the title “Choose Your Media Player”"))
                players
            }
            .windowMargins()
            BottomBar(margin: HostedWindowController.margin) {
                Spacer()
                Button { continueTapped() } label: {
                    Text("Continue", comment: "Button in the welcome window and the Add a Web App window: goes on with what's chosen or typed")
                        .font(.appBody.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                .keyboardShortcut(.defaultAction) // the search, when it shows, keeps Return: `returnInSearch`
                .disabled(!canContinue)
            }
        }
        .frame(width: Self.width)
    }

    /// The search, the tiles and the note about what's installed.
    @ViewBuilder private var players: some View {
        if model.playerOptions.isSearchable {
            SearchField(text: $search, onSubmit: returnInSearch)
        }
        PlayerTiles(options: model.playerOptions.offered.matching(search), selection: picked,
                    onSelect: select,
                    onAddWebApp: { model.addWebApp() },
                    maxVisibleRows: Self.visibleTileRows,
                    holdsHeight: !search.isEmpty, // typing doesn't shrink the window
                    search: search)
        if model.playerOptions.noneInstalled {
            NoteLabel(PlayerOption.noneInstalledWarning)
        } else if let note = PlayerOption.onlyInstalledNote(among: model.playerOptions) {
            NoteLabel(note, kind: .info)
        }
    }

    /// Its content as tall as it wants, or `limit` tall when that's less: the
    /// content then has to fit, as a list in it does by scrolling.
    private struct HeightLimit: Layout {
        let limit: CGFloat?

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let content = subviews.first else { return .zero }
            return content.sizeThatFits(contentProposal(width: proposal.width, content))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard let content = subviews.first else { return }
            content.place(at: bounds.origin, proposal: contentProposal(width: bounds.width, content))
        }

        /// Its ideal height, unless that's more than `limit`.
        private func contentProposal(width: CGFloat?, _ content: LayoutSubview) -> ProposedViewSize {
            let ideal = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
            guard let limit, ideal.height > limit else { return ProposedViewSize(width: width, height: nil) }
            return ProposedViewSize(width: width, height: limit)
        }
    }

    /// A click on a tile: a suggested web app opens "Add a Web App" filled
    /// in; a player is picked.
    private func select(_ option: PlayerOption) {
        if option.webAddress != nil { model.chooseMusicPlayer(option.bundleID) } else { clicked = option.bundleID }
    }

    private func continueTapped() {
        if let picked { model.chooseMusicPlayer(picked) }
    }

    /// Return in the search, which has the keyboard from the start and keeps
    /// Return from Continue: with nothing typed, it's Continue; with a
    /// search, it picks the one player the search narrowed down to, as a
    /// click on its tile would, and nothing while more match, or none.
    private func returnInSearch() {
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            if canContinue { continueTapped() }
        } else if let only = Self.onlyMatch(of: model.playerOptions.offered, search: search) {
            select(only)
        }
    }

    /// The one player `search` narrows `options` down to, when it can be
    /// picked (installed, or a suggested web app); `nil` otherwise. Tiles
    /// that share a name, as the Spotify app and the suggested Spotify web
    /// app do, count as one: the app first, then an added web app, then a
    /// suggested one.
    static func onlyMatch(of options: [PlayerOption], search: String) -> PlayerOption? {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let matches = options.matching(search)
        guard Set(matches.map { $0.name.lowercased() }).count == 1 else { return nil }
        return matches.filter(\.isClickable).min { pickOrder($0) < pickOrder($1) }
    }

    /// Among tiles of one name: the app, an added web app, a suggested one.
    private static func pickOrder(_ option: PlayerOption) -> Int {
        option.kind == .app ? 0 : option.isInstalled ? 1 : 2
    }

    /// A player is picked, and is still installed.
    private var canContinue: Bool {
        model.playerOptions.contains { $0.bundleID == picked && $0.isInstalled }
    }
}
