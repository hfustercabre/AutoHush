import SwiftUI
import AutoHushKit

/// "Ignored Apps": the apps switched off (V5, the user's pick, 2026-10-18):
/// the part's title over a row with up to three of their icons, their names
/// and what they are, and a chevron; a click opens them in a side window
/// beside the menu, each with its switch (W2).
struct MenuIgnoredAppsView: View {
    let model: StatusMenuModel

    /// Those ignored now; while its side window is open and every one was
    /// switched back on, those it lists (once it closes, none: they pause
    /// the player again).
    private var apps: [AudioSource] {
        model.showsIgnoredApps && model.status.ignoredApps.isEmpty ? model.listedIgnoredApps : model.status.ignoredApps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuPartTitle(Text(verbatim: Self.title))
            // None yet: "None" and what ignoring does (N1, the user's pick,
            // 2026-10-18), and its side window offers Ignore Another App….
            MenuSideRow(title: apps.isEmpty ? NoneText.title : Self.names(of: apps.map(\.name)),
                        subtitle: Self.subtitle(count: apps.count),
                        leadingWidth: MenuSpacing.row.picture + (apps.count > 1 ? 10 : 0), isOpen: model.showsIgnoredApps,
                        action: { model.perform(.openSide(.ignoredApps)) },
                        onHover: { model.perform(.hoverSideRow(.ignoredApps, $0)) },
                        onTop: { model.sideRowTops[.ignoredApps] = $0 }) {
                iconStack
            }
        }
        .frame(width: menuContentWidth)
    }

    /// Under the apps' names, as many as are ignored (U1, the user,
    /// 2026-10-19: one app in the singular); under "None", what ignoring one
    /// does.
    static func subtitle(count: Int) -> String {
        switch count {
        case 0:
            String(localized: "Apps you ignore don’t pause your player.",
                   comment: "The menu, Ignored Apps, under “None” while no app is ignored: what ignoring an app does")
        case 1:
            String(localized: "It doesn’t pause your player.",
                   comment: "The menu, Ignored Apps, under the name of the one app ignored")
        default:
            String(localized: "They don’t pause your player.",
                   comment: "The menu, Ignored Apps, under the names of the ignored apps (two or more)")
        }
    }

    /// The part's title, over its row and atop its side window.
    static var title: String {
        String(localized: "Ignored Apps", comment: "The menu: heading over the apps that don’t pause your player")
    }

    /// The apps' names in a few words: one or two named; from three on, the
    /// first two and how many more.
    static func names(of names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: ListFormatter.localizedString(byJoining: names)
        default:
            String(localized: "\(names[0]), \(names[1]) and \(names.count - 2) more",
                   comment: "The menu, Ignored Apps: the first two ignored apps' names, then how many others there are (1 or more)")
        }
    }

    private func icon(_ app: AudioSource) -> some View {
        Image(nsImage: AppIcon.image(for: app, players: model.status.playerOptions, size: 18))
            .resizable()
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    /// Up to three of the apps' icons, overlapping; one alone where the
    /// other rows have theirs.
    @ViewBuilder private var iconStack: some View {
        if apps.isEmpty {
            MenuRowSymbol("speaker.slash")
        } else {
            ZStack(alignment: .leading) {
                // By app: one that comes or goes leaves the others' icons be.
                ForEach(Array(apps.prefix(3).enumerated()), id: \.element.id) { index, app in
                    icon(app).offset(x: CGFloat(index) * 7)
                }
            }
        }
    }
}
