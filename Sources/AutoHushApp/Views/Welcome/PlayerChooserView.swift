import AppKit
import AutoHushKit
import SwiftUI

/// The media players as tiles, as in Settings → General (`PlayerTiles`): the
/// apps, then the Safari web apps and the tile that adds one; the user picks
/// one and continues.
/// Players that aren't installed come after the installed apps, dimmed, and
/// can't be picked. Past `visibleTileRows` rows of tiles, they scroll. From
/// `PlayerOption.searchThreshold` players on, a search narrows them down.
struct PlayerChooserView: View {
    let model: SettingsModel
    /// The tallest the first page may be: past it, its list scrolls. `nil`:
    /// as tall as the players make it.
    var tallestPage: CGFloat?
    /// The player the user picked.
    @State private var picked: String?
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
                             description: Text("AutoHush pauses it while other apps play audio, then resumes it. You can change it anytime in the menu or Settings.",
                                               comment: "Welcome window, at its top beside AutoHush's icon, under the title “Choose Your Media Player”"))
                players
            }
            .windowMargins()
            BottomBar {
                Spacer()
                // The search, when it shows, keeps Return: `returnInSearch`.
                MainButton(AddAppText.continueButton) { continueTapped() }
                    .disabled(!canContinue)
            }
        }
        .frame(width: Self.width)
    }

    /// The search and the tiles.
    @ViewBuilder private var players: some View {
        if model.playerOptions.isSearchable {
            SearchField(text: $search, onSubmit: returnInSearch)
        }
        PlayerTiles(options: model.offeredPlayers.matching(search), selection: picked,
                    onSelect: select,
                    onAddWebApp: { model.actions?.openAddWebApp() },
                    onAddApp: { model.actions?.openAddApp() },
                    onRemove: { model.actions?.removeAddedApp($0.bundleID) },
                    maxVisibleRows: Self.visibleTileRows,
                    holdsHeight: !search.isEmpty, // typing doesn't shrink the window
                    search: search)
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
        if option.webAddress != nil { model.actions?.choosePlayer(option.bundleID) } else { picked = option.bundleID }
    }

    private func continueTapped() {
        if let picked { model.actions?.choosePlayer(picked) }
    }

    /// Return in the search, which has the keyboard from the start and keeps
    /// Return from Continue: with nothing typed, it's Continue; with a
    /// search, it picks the one player the search narrowed down to, as a
    /// click on its tile would, and nothing while more match, or none.
    private func returnInSearch() {
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            if canContinue { continueTapped() }
        } else if let only = Self.onlyMatch(of: model.offeredPlayers, search: search) {
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
        option.kind != .safariWebApp ? 0 : option.isInstalled ? 1 : 2
    }

    /// A player is picked, and is still installed and can be chosen.
    private var canContinue: Bool {
        model.offeredPlayers.contains { $0.bundleID == picked && $0.isInstalled && $0.isClickable }
    }
}
