import SwiftUI

/// The media players in their side window beside the menu (`MenuSidePanelView`,
/// W2, the user's pick, 2026-10-18): the search (from
/// `PlayerOption.searchThreshold` players on), then the supported apps, the
/// apps added with Add an App (and Add an App…) and the Safari web apps (and
/// Add a Web App…), each under its section title, a line between them. The
/// chosen one is checked. As in the menu, the arrow keys and the pointer
/// move the highlight (the side window's `KeyHighlight`) through the rows,
/// the tint behind it, and Return or Space presses the row; typing goes to
/// the search, Return then choosing the first player it left. With Option held, an added app's row removes it, after
/// asking (R5).
struct MenuPlayerListView: View {
    let model: StatusMenuModel

    var body: some View {
        let list = model.players
        VStack(alignment: .leading, spacing: 6) {
            if list.showsSearch {
                // The menu keeps the keyboard, typing reaching the search all the
                // same; a click in it, or a key only the field can compose, gives
                // it the keyboard (`StatusMenuController.searchTakesKeyboard`).
                SearchField(text: Binding(get: { model.playerSearch }, set: { model.perform(.searchPlayers($0)) }),
                            focusRequest: model.searchFocus,
                            onClick: { model.perform(.typeInSearch) },
                            onSubmit: { model.perform(.chooseHighlighted) },
                            onMove: { model.perform(.moveHighlight($0)) })
            }
            if let note = list.noMatchNote {
                Text(verbatim: note).captionStyle()
            }
            if !list.supportedApps.isEmpty {
                CardDivider()
                SectionLabel(Text(verbatim: PlayerOption.supportedAppsHeading))
                    .accessibilityAddTraits(.isHeader)
                rows(list.supportedApps)
            }
            if list.showsOtherApps {
                CardDivider()
                OtherAppsHeading(isEmpty: list.otherApps.isEmpty)
                rows(list.otherApps)
                addRow(PlayerOption.addAppTitle, .addApp)
            }
            CardDivider()
            if !list.webApps.isEmpty {
                WebAppsHeading()
                rows(list.webApps)
            }
            addRow(PlayerOption.addWebAppTitle, .addWebApp)
        }
    }

    /// Its rows' picture column (their 18 pt icons) and the gap to their
    /// names, from the side window's margin.
    static let rowLayout = MenuSpacing.RowLayout(leading: 14, picture: 18, gap: 8)

    private func rows(_ rows: [MenuPlayerList.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                let removes = model.isOptionHeld && row.isRemovable
                MenuActionRow(place: .sideWindow, layout: Self.rowLayout, action: {
                    // With Option held as it's pressed, an added app is removed.
                    model.perform(model.isOptionHeld && row.isRemovable ? .removeAddedApp(row.id) : .choosePlayer(row.id))
                }) {
                    Image(nsImage: row.option.icon(size: 18))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(verbatim: removes ? PlayerOption.removeTitle(row.option.name) : row.option.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if row.option.isUntested, !removes { HeadingBadge(text: PlayerOption.untestedBadge) }
                        }
                        if let subtitle = row.subtitle, !removes { MenuRowSubtitle(text: subtitle) }
                    }
                    Spacer(minLength: 4)
                    if row.isChosen, !removes {
                        Image(systemName: "checkmark")
                            .font(.callout.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .disabled(!row.isEnabled && !removes)
                .help(row.help.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
                .accessibilityLabel(Text(verbatim: removes ? PlayerOption.removeTitle(row.option.name) : row.accessibilityLabel))
                .accessibilityHint(row.help.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
                .accessibilityAddTraits(row.isChosen ? .isSelected : [])
            }
        }
    }

    private func addRow(_ title: String, _ command: StatusMenuCommand) -> some View {
        MenuActionRow(place: .sideWindow, layout: Self.rowLayout, action: { model.perform(command) }) {
            Image(systemName: "plus.circle").accessibilityHidden(true)
        } content: {
            Text(verbatim: title)
        }
    }
}
