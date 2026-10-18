import SwiftUI

/// The media players in their side window beside the menu (`MenuSidePanelView`,
/// W2, the user's pick, 2026-10-18): the search (from
/// `PlayerOption.searchThreshold` players on), then the supported apps, the
/// apps added with Add an App (and Add an App…) and the Safari web apps (and
/// Add a Web App…), each under its section title, a line between them. The chosen one is checked; ↑ and ↓
/// move among them and Return chooses, as in a menu. With Option held, an
/// added app's row removes it, after asking (R5).
struct MenuPlayerListView: View {
    let model: StatusMenuModel

    var body: some View {
        let list = model.players
        VStack(alignment: .leading, spacing: 6) {
            if list.showsSearch {
                SearchField(text: Binding(get: { model.playerSearch }, set: { model.perform(.searchPlayers($0)) }),
                            focusesOnAppear: false, // the menu keeps the keyboard: typing reaches it all the same
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

    private func rows(_ rows: [MenuPlayerList.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                let removes = model.isOptionHeld && row.isRemovable
                Button {
                    model.perform(removes ? .removeAddedApp(row.id) : .choosePlayer(row.id))
                } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: row.option.icon(size: 18))
                            .resizable()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
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
                }
                .buttonStyle(MenuRowButtonStyle(isHighlighted: model.highlightedPlayerID == row.id))
                .disabled(!row.isEnabled && !removes)
                .help(row.help.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
                .accessibilityLabel(Text(verbatim: removes ? PlayerOption.removeTitle(row.option.name) : row.accessibilityLabel))
                .accessibilityHint(row.help.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
                .accessibilityAddTraits(row.isChosen ? .isSelected : [])
                .padding(.horizontal, -6)
            }
        }
    }

    private func addRow(_ title: String, _ command: StatusMenuCommand) -> some View {
        Button { model.perform(command) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(verbatim: title)
            }
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(.horizontal, -6)
    }
}
