import AppKit
import SwiftUI

/// Settings → About, A4 (the user's pick, 2026-10-26: "its too crowded"
/// once Updates came here): the app's icon, name, version and what it does,
/// centered (H1, 2026-10-31), the icon beside the name and the version
/// in a window too short for them (M5, 2026-10-31); its updates (`UpdatesCard`, a page of their
/// own until W1, the user, 2026-10-25); links to the project; the
/// copyright. It fits the window without scrolling. The players it works with are on the Media
/// Player page, and the way to support it at the sidebar's foot. The menu's
/// About button opens it.
struct AboutSettingsView: View {
    let model: SettingsModel
    /// The icon's side, fitted to the page (`fittedIconSize`); the name
    /// grows and shrinks with it.
    @State private var iconSize: CGFloat = 96
    /// The page's size, its content's height (padding included) and the
    /// name's size as last measured, and the icon's side each of the last two
    /// was measured beside: a fit waits until the content is of the icon
    /// shown and the name was measured once, as the name is measured after
    /// the content (it stayed 96 pt until the window was resized,
    /// 2026-10-31); the name's size is then scaled to the icon (`nameSize`).
    @State private var pageSize: CGSize = .zero
    @State private var contentHeight: CGFloat = 0
    @State private var nameSize: CGSize = .zero
    @State private var measuredBeside = (content: CGFloat(0), name: CGFloat(0))
    /// The icon beside the name and the version (`compactHeader`): the page
    /// is too short for them on lines of their own even at `leastIconSize`
    /// (M5, the user's pick, 2026-10-31). Then the content's height as last
    /// measured, and how much taller the stacked header at `leastIconSize`
    /// made it, measured as it changed over.
    @State private var isCompact = false
    @State private var compactHeight: CGFloat = 0
    @State private var stackedAtLeast: CGFloat = 0
    @State private var stackedExtra: CGFloat = 0

    /// The icon's least and largest sides, and the name's text size to it
    /// (17 pt beside 96, 23 beside 128): it resizes a little, at most to
    /// F2's 128 pt and 23 pt (the user, 2026-10-31: "making it resize but
    /// only a little? At most as the F2"), and shrinks so the copyright
    /// line fits the window's minimum size in the page's tallest case (no
    /// automatic checks, a release candidate offered, Restore Defaults).
    nonisolated static let leastIconSize: CGFloat = 64
    nonisolated static let largestIconSize: CGFloat = 128
    nonisolated static let nameRatio: CGFloat = 23 / 128
    /// The least a fit grows the icon by (`fittedIconSize`).
    nonisolated static let leastGrowth: CGFloat = 3
    /// The icon's side beside the name.
    nonisolated static let compactIconSize: CGFloat = 56

    var body: some View {
        GeometryReader { page in
            ScrollViewReader { scroller in
                ScrollView {
                    content
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            if isCompact {
                                compactHeight = height
                                if stackedExtra == 0 { stackedExtra = stackedAtLeast - height }
                            } else {
                                contentHeight = height
                                measuredBeside.content = iconSize
                            }
                            fit()
                        }
                        // Centered in the page however tall the window is (the
                        // user, 2026-10-31: "make it so it always stay
                        // centered"); a page too short for it scrolls, as before.
                        .frame(minHeight: page.size.height)
                }
                // The arrow keys' highlight scrolls into view, as on the other pages.
                .revealsKeyHighlight(with: scroller)
            }
            .onChange(of: page.size, initial: true) {
                pageSize = page.size
                fit()
            }
        }
    }

    /// Fits the icon, and the name with it, to the page's room, once the
    /// content is measured beside the icon shown and the name once; puts
    /// the icon beside the name when even `leastIconSize` doesn't fit, and
    /// back on its own line once it does.
    private func fit() {
        if isCompact {
            guard compactHeight > 0, stackedExtra > 0 else { return }
            if Self.stackedFits(page: pageSize, compactContent: compactHeight, stackedExtra: stackedExtra) {
                isCompact = false
            }
            return
        }
        guard measuredBeside.content == iconSize, measuredBeside.name > 0 else { return }
        let name = Self.nameSize(nameSize, measuredBeside: measuredBeside.name, at: iconSize)
        let atLeast = Self.contentHeight(atIcon: Self.leastIconSize, current: iconSize, content: contentHeight, name: name)
        if pageSize.height > 0, atLeast > pageSize.height + 0.5 {
            stackedAtLeast = atLeast
            stackedExtra = 0
            iconSize = Self.leastIconSize
            isCompact = true
            return
        }
        let fitted = Self.fittedIconSize(current: iconSize, page: pageSize, content: contentHeight, name: name)
        if abs(fitted - iconSize) >= 1 { iconSize = fitted }
    }

    /// The name's size beside an icon of `side`, from one measured beside
    /// `measured`: its font follows the icon, and its size with it. A 1 pt
    /// step may leave the name's rounded size as it was, so it isn't
    /// measured again: the fit would have waited for good (on a 1x screen,
    /// the 1.2.9 review).
    nonisolated static func nameSize(_ size: CGSize, measuredBeside measured: CGFloat, at side: CGFloat) -> CGSize {
        guard measured > 0 else { return size }
        return CGSize(width: size.width * side / measured, height: size.height * side / measured)
    }

    /// The content's height with the icon at `side`, from one measured
    /// beside `current`: the icon's and the name's heights follow it.
    nonisolated static func contentHeight(atIcon side: CGFloat, current: CGFloat, content: CGFloat, name: CGSize) -> CGFloat {
        guard current > 0 else { return content }
        return content - (current - side) - name.height * (1 - side / current)
    }

    /// The stacked header fits again at `leastIconSize`, with 2 pt to spare
    /// so the two headers never take turns (the compact one went in at 0.5
    /// over).
    nonisolated static func stackedFits(page: CGSize, compactContent: CGFloat, stackedExtra: CGFloat) -> Bool {
        page.height > 0 && compactContent + stackedExtra <= page.height - 2
    }

    /// The icon's side that makes the page as tall as `page` (its room
    /// shared by the icon and the name, whose height follows it), within
    /// `leastIconSize`…`largestIconSize`, the name kept on one line, grown
    /// only by `leastGrowth` or more while the room is tight.
    /// Nothing measured yet, the page's size included: `current`.
    nonisolated static func fittedIconSize(current: CGFloat, page: CGSize, content: CGFloat, name: CGSize) -> CGFloat {
        guard current > 0, page.width > 0, page.height > 0, content > 0, name.width > 0, name.height > 0 else { return current }
        let fixed = content - current - name.height
        let byHeight = (page.height - fixed) / (1 + name.height / current)
        let byName = (page.width - 2 * 20) * current / name.width
        let room = min(byHeight, byName)
        let fitted = max(leastIconSize, min(room, largestIconSize)).rounded(.down)
        // It shrinks at once but grows only by `leastGrowth` or more, unless
        // the room is that much larger: the name's line height steps with
        // its font, so 1 pt more can overflow again, and the two sizes took
        // turns for good (79 and 80 pt at the window's minimum size,
        // 2026-10-31).
        let tight = room < fitted + leastGrowth
        return tight && fitted > current && fitted < current + leastGrowth ? current : fitted
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            if isCompact { compactHeader } else { header }
            UpdatesCard(model: model)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                link(Text(verbatim: "GitHub"), symbol: "chevron.left.forwardslash.chevron.right", to: ProjectInfo.homepage)
                link(Text("What’s New", comment: "Settings → About: opens the release notes on GitHub"),
                     symbol: "sparkles", to: ProjectInfo.whatsNewPage(for: model.currentVersion.flatMap(AppVersion.init)))
                link(Text("Report an Issue", comment: "Settings → About: opens a new issue on GitHub"),
                     symbol: "ladybug", to: ProjectInfo.newIssuePage)
                Spacer(minLength: 0)
            }
            if let copyright = Self.copyright {
                Text(verbatim: copyright)
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The icon, the name, the version and what AutoHush does, each on a
    /// line of its own, centered, as macOS's About windows (H1, the user's
    /// pick, 2026-10-31), the icon and the name sized by `iconSize`.
    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            Text(verbatim: "AutoHush")
                .font(.appAboutTitle(iconSize: iconSize))
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                    nameSize = size
                    measuredBeside.name = iconSize
                    fit()
                }
            version
            tagline
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// In a window too short for `header` (M5, 2026-10-31): the icon beside
    /// the name and the version, the tagline under them.
    private var compactHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: Self.compactIconSize, height: Self.compactIconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "AutoHush")
                        .font(.appAboutTitle(iconSize: 96))
                        .fixedSize()
                    version
                }
            }
            tagline
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var version: some View {
        if let version = model.fullVersion {
            Text(verbatim: AutoHushText.version(version))
                .foregroundStyle(.appSecondary)
                .textSelection(.enabled)
        }
    }

    /// The README's tagline (the user, 2026-10-31).
    private var tagline: some View {
        Text("Whatever’s playing steps aside when something else needs your ears.",
             comment: "Settings → About, centered under the app's icon, name and version: what AutoHush does, as the README's tagline says it: the media player's playback (music, podcasts, videos) pauses while another app plays sound")
            .foregroundStyle(.appSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func link(_ title: Text, symbol: String, to url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label { title } icon: { Image(systemName: symbol) }
        }
        .buttonStyle(.chip)
        .help(url.absoluteString)
    }

    /// The copyright line from Info.plist, in the app's language.
    private static var copyright: String? {
        (Bundle.main.localizedInfoDictionary?["NSHumanReadableCopyright"]
            ?? Bundle.main.infoDictionary?["NSHumanReadableCopyright"]) as? String
    }
}
