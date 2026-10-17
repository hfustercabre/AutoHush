import SwiftUI

/// The media players as tiles, three a row, in one card: the apps under
/// "Supported Apps", the apps added through a check under "Other Apps" (E3),
/// then the Safari web apps under their heading; each of the last two groups
/// with a tile that adds one. A tile is a chip: the player's icon, then its name
/// with what a row would say under it, shorter. The chosen (or picked)
/// player's tile is tinted and outlined with the accent color, even while
/// AntiDot mode keeps it from being chosen (an app only its sound tells
/// about).
/// Settings → General and the welcome window show them; the menu keeps its
/// rows.
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
    /// "Add an App…": checks an app and adds it.
    var onAddApp: () -> Void = {}
    /// An app added with Add an App: its × (under the pointer, or with the
    /// keyboard on its tile) or its right-click menu removes it, once the
    /// user confirms (R2, the user's pick, 2026-10-15).
    var onRemove: ((PlayerOption) -> Void)?
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
    @State private var otherAppsTop: CGFloat = 0
    @State private var webAppsTop: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var heldHeight: CGFloat?

    private var apps: [PlayerOption] { options.filter { $0.kind == .app } }
    private var checkedApps: [PlayerOption] { options.filter { $0.kind == .checkedApp } }
    private var webApps: [PlayerOption] { options.filter { $0.kind == .safariWebApp } }

    /// What an add tile adds.
    private enum Adds { case app, webApp }

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

    /// The groups' tiles under their headings, spaced as a card's rows.
    private var groups: some View {
        VStack(alignment: .leading, spacing: 10) {
            if apps.isEmpty && checkedApps.isEmpty && webApps.isEmpty && !search.isEmpty {
                Text(verbatim: PlayerOption.noMatchNote(search)).foregroundStyle(.appSecondary)
            }
            if !apps.isEmpty {
                SectionLabel(Text(verbatim: PlayerOption.supportedAppsHeading))
                    .accessibilityAddTraits(.isHeader)
                grid(apps, adds: nil)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).minY }) { appsTop = $0 }
                CardDivider()
            }
            OtherAppsHeading(isEmpty: checkedApps.isEmpty)
            grid(checkedApps, adds: .app)
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).minY }) { otherAppsTop = $0 }
            CardDivider()
            WebAppsHeading()
            grid(webApps, adds: .webApp)
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).minY }) { webAppsTop = $0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid(_ options: [PlayerOption], adds: Adds?) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns), spacing: Self.rowSpacing) {
            ForEach(options) { tile($0) }
            if let adds { addTile(adds) }
        }
    }

    /// The tiles as tall as their first `rows` rows, counting each group's
    /// in turn (with their headings between), a little of the next row's
    /// room under them; all of them when there are no more.
    private func visibleHeight(rows: Int) -> CGFloat {
        let groups = (apps.isEmpty ? [] : [(rows: Self.rowCount(apps.count), top: appsTop)])
            + [(rows: Self.rowCount(checkedApps.count + 1), top: otherAppsTop), // the add tiles
               (rows: Self.rowCount(webApps.count + 1), top: webAppsTop)]
        return Self.visibleHeight(rows: rows, groups: groups, contentHeight: contentHeight)
    }

    /// The same for `groups`, each its rows and where its tiles start, in
    /// tiles `contentHeight` tall in all (0 until measured).
    static func visibleHeight(rows: Int, groups: [(rows: Int, top: CGFloat)], contentHeight: CGFloat) -> CGFloat {
        guard groups.map(\.rows).reduce(0, +) > rows, contentHeight > 0 else { return contentHeight }
        var left = rows
        var bottom = contentHeight
        for group in groups {
            if left <= group.rows {
                bottom = group.top + height(ofRows: left)
                break
            }
            left -= group.rows
        }
        return min(contentHeight, bottom + rowSpacing + 12)
    }

    static func rowCount(_ tiles: Int) -> Int { (tiles + columns - 1) / columns }

    static func height(ofRows rows: Int) -> CGFloat {
        rows > 0 ? CGFloat(rows) * tileHeight + CGFloat(rows - 1) * rowSpacing : 0
    }

    /// A player: its icon, then its name with what a row would say under it
    /// (Click to add, Untested, Not installed, Muted only); tinted and
    /// outlined once chosen. Dimmed while it can't be chosen; in AntiDot
    /// mode, an app only its sound tells about says why in its help tag and
    /// VoiceOver hint. An app added with Add an App shows a × under the
    /// pointer or the keyboard, and can be removed from its right-click menu.
    @ViewBuilder private func tile(_ option: PlayerOption) -> some View {
        let button = tileButton(option)
        let explained = Group {
            if option.isInstalled && option.isUnavailableInAntiDotMode {
                // Outside the disabled button, so the help tag still shows.
                button
                    .help(option.antiDotModeReason)
                    .accessibilityHint(Text(verbatim: option.antiDotModeReason))
            } else {
                button
            }
        }
        if option.kind == .checkedApp, let onRemove {
            RemovableTile(name: option.name) { onRemove(option) } content: { explained }
        } else {
            explained
        }
    }

    private func tileButton(_ option: PlayerOption) -> some View {
        let isSelected = option.bundleID == selection && option.isInstalled
        return Button { onSelect(option) } label: {
            HStack(spacing: 8) {
                Image(nsImage: option.icon(size: Self.iconSize))
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: option.name).font(.appCallout).lineLimit(1).minimumScaleFactor(0.85)
                        .accessibilityLabel(Text(verbatim: option.spokenName(among: options)))
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
            Text(verbatim: PlayerOption.clickToAddLabel)
                .font(.appCaption).foregroundStyle(.appSecondary).lineLimit(1)
        } else if option.isUntested {
            HeadingBadge(text: PlayerOption.untestedBadge)
        } else if !option.isInstalled {
            Text(verbatim: PlayerOption.notInstalledLabel).font(.appCaption).foregroundStyle(.appSecondary).lineLimit(1)
        } else if option.isUnavailableInAntiDotMode {
            Text(verbatim: PlayerOption.antiDotModeTileLabel).font(.appCaption).foregroundStyle(.appSecondary).lineLimit(1)
        } else if option.pausesByMuting {
            Text(verbatim: PlayerOption.mutedOnlyLabel).font(.appCaption).foregroundStyle(.appSecondary).lineLimit(1)
        }
    }

    /// The room inside a tile, before its icon.
    private static let inset: CGFloat = 6

    /// The last tile of the other apps (checks an app and adds it) and of
    /// the Safari web apps (adds one).
    private func addTile(_ adds: Adds) -> some View {
        Button(action: adds == .app ? onAddApp : onAddWebApp) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                Text("Add…", comment: "The last tile of the Safari web apps and of the other apps (Settings → General, the welcome window): adds a website as a web app, or checks an app and adds it")
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
        .accessibilityLabel(Text(verbatim: adds == .app ? PlayerOption.addAppTitle : PlayerOption.addWebAppTitle))
    }
}

/// An added app's tile with a × in its corner while the pointer is over it,
/// or the keyboard is on it or its × (Tab, with keyboard navigation on),
/// which removes it once confirmed; its right-click menu and VoiceOver have
/// it too.
private struct RemovableTile<Content: View>: View {
    let name: String
    let remove: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false
    @FocusState private var focus: Focus?

    private enum Focus { case tile, remove }

    var body: some View {
        content
            .focused($focus, equals: .tile)
            .overlay(alignment: .topTrailing) {
                if isHovered || focus != nil {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .appSecondary)
                    }
                    .buttonStyle(.plain)
                    .focused($focus, equals: .remove)
                    .help(PlayerOption.removeTitle(name))
                    .accessibilityLabel(Text(verbatim: PlayerOption.removeTitle(name)))
                    .offset(x: 5, y: -5)
                }
            }
            .onHover { isHovered = $0 }
            .contextMenu { Button(PlayerOption.removeTitle(name), action: remove) }
            .accessibilityAction(named: Text(verbatim: PlayerOption.removeTitle(name)), remove)
    }
}
