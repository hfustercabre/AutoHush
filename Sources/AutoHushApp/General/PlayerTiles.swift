import SwiftUI

/// The media players as tiles, three a row, in one card: the apps under
/// "Supported Apps", then the Safari web apps under their heading, with a
/// tile that adds one. A tile is a chip: the player's icon, then its name
/// with what a row would say under it. The chosen (or picked) player's
/// tile is tinted and outlined with the accent color. Settings → General and
/// the welcome window show them; the menu keeps its rows.
///
/// With `maxVisibleRows`, the card shows that many rows of tiles at most,
/// counting both groups, and they scroll inside it past them (the card
/// stays put: scrolled itself, its rounded corners would be clipped); while
/// `holdsHeight`, it keeps the height it has (a search narrowing the tiles
/// doesn't shrink the window).
struct PlayerTiles: View {
    let options: [PlayerOption]
    /// The chosen or picked player, tinted and outlined.
    let selection: String?
    /// A click on an installed player, or on a suggested web app (which then
    /// opens "Add a Web App" filled in).
    let onSelect: (PlayerOption) -> Void
    let onAddWebApp: () -> Void
    var maxVisibleRows: Int?
    var holdsHeight = false
    /// What was typed, for the note when nothing matches.
    var search = ""

    static let columns = 3
    /// Every tile is this tall, with or without a word under its name, so
    /// the rows are even and the visible rows can be counted.
    static let tileHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 8
    static let iconSize: CGFloat = 24

    @State private var appsTop: CGFloat = 0
    @State private var webAppsTop: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var heldHeight: CGFloat?

    private var apps: [PlayerOption] { options.filter { $0.kind == .app } }
    private var webApps: [PlayerOption] { options.filter { $0.kind != .app } }

    var body: some View {
        Card {
            if let maxVisibleRows {
                ScrollView {
                    groups.coordinateSpace(.named(Self.space))
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                }
                .frame(height: heldHeight ?? visibleHeight(rows: maxVisibleRows))
                .onChange(of: holdsHeight) { _, holds in
                    heldHeight = holds ? visibleHeight(rows: maxVisibleRows) : nil
                }
            } else {
                groups
            }
        }
    }

    private nonisolated static let space = "PlayerTiles"

    /// The apps' and the web apps' tiles under their headings, spaced as a
    /// card's rows.
    private var groups: some View {
        VStack(alignment: .leading, spacing: 10) {
            if apps.isEmpty && webApps.isEmpty && !search.isEmpty {
                Text(verbatim: PlayerOption.noMatchNote(search)).foregroundStyle(.appSecondary)
            }
            if !apps.isEmpty {
                SectionLabel(Text(verbatim: PlayerOption.supportedAppsHeading))
                    .accessibilityAddTraits(.isHeader)
                grid(apps, adds: false)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).minY }) { appsTop = $0 }
                CardDivider()
            }
            WebAppsHeading()
            grid(webApps, adds: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).minY }) { webAppsTop = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid(_ options: [PlayerOption], adds: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns), spacing: Self.rowSpacing) {
            ForEach(options) { tile($0) }
            if adds { addTile }
        }
    }

    /// The tiles as tall as their first `rows` rows, counting the apps' then
    /// the web apps' (with their heading between), a little of the next
    /// row's room under them; all of them when there are no more.
    private func visibleHeight(rows: Int) -> CGFloat {
        let appRows = Self.rowCount(apps.count)
        let webAppRows = Self.rowCount(webApps.count + 1) // the add tile
        guard appRows + webAppRows > rows, contentHeight > 0 else { return contentHeight }
        let bottom = appRows >= rows
            ? appsTop + Self.height(ofRows: rows)
            : webAppsTop + Self.height(ofRows: rows - appRows)
        return min(contentHeight, bottom + Self.rowSpacing + 12)
    }

    static func rowCount(_ tiles: Int) -> Int { (tiles + columns - 1) / columns }

    static func height(ofRows rows: Int) -> CGFloat {
        rows > 0 ? CGFloat(rows) * tileHeight + CGFloat(rows - 1) * rowSpacing : 0
    }

    /// A player: its icon, then its name with what a row would say under it
    /// (Click to add, Untested, Not installed); tinted and outlined once
    /// chosen. Dimmed while it can't be chosen.
    private func tile(_ option: PlayerOption) -> some View {
        let isSelected = option.bundleID == selection && option.isInstalled
        return Button { onSelect(option) } label: {
            HStack(spacing: 8) {
                Image(nsImage: option.icon(size: Self.iconSize))
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: option.name).font(.appCallout).lineLimit(1).minimumScaleFactor(0.85)
                    note(option)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Self.inset)
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.selectedTileFill) }
            }
            // Chosen: outlined in the accent color too, so the whole name fits.
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ChipButtonStyle(cornerRadius: 10)) // lights up under the pointer; dims while disabled
        .disabled(!option.isClickable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func note(_ option: PlayerOption) -> some View {
        if option.webAddress != nil {
            Text("Click to add", comment: "Under a suggested Safari web app's tile (Settings → General, the welcome window): a click adds it. Keep it short (about 12 characters): a plain “Add” is fine")
                .font(.appCaption).foregroundStyle(.appSecondary).lineLimit(1)
        } else if option.isUntested {
            HeadingBadge(text: PlayerOption.untestedBadge)
        } else if !option.isInstalled {
            Text(verbatim: PlayerOption.notInstalledLabel).font(.appCaption).foregroundStyle(.appSecondary).lineLimit(1)
        }
    }

    /// The room inside a tile, before its icon.
    private static let inset: CGFloat = 6

    /// The last tile: adds a Safari web app.
    private var addTile: some View {
        Button(action: onAddWebApp) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                Text("Add…", comment: "The last of the Safari web apps' tiles (Settings → General, the welcome window): adds a website as a web app")
                    .font(.appCallout)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.appSecondary)
            .padding(.horizontal, Self.inset)
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ChipButtonStyle(cornerRadius: 10))
        .accessibilityLabel(Text(verbatim: PlayerOption.addWebAppTitle))
    }
}
