import AppKit
import SwiftUI

/// Settings → About, A4 (the user's pick, 2026-10-26: "its too crowded"
/// once Updates came here): the app's icon, name, version and what it does,
/// centered (H1, 2026-10-31); its updates (`UpdatesCard`, a page of their
/// own until W1, the user, 2026-10-25); links to the project; the
/// copyright. It fits the window without scrolling. The players it works with are on the Media
/// Player page, and the way to support it at the sidebar's foot. The menu's
/// About button opens it.
struct AboutSettingsView: View {
    let model: SettingsModel
    /// The icon's side, fitted to the page (`fittedIconSize`); the name
    /// grows and shrinks with it.
    @State private var iconSize: CGFloat = 96
    /// The page's content as last measured, padding included, and the name's.
    @State private var contentHeight: CGFloat = 0
    @State private var nameSize: CGSize = .zero

    /// The icon's least and largest sides, and the name's text size to it
    /// (17 pt beside 96, 23 beside 128): it resizes a little, at most to
    /// F2's 128 pt and 23 pt (the user, 2026-10-31: "making it resize but
    /// only a little? At most as the F2"), and shrinks so the copyright
    /// line fits the window's minimum size in the page's tallest case (no
    /// automatic checks, a release candidate offered, Restore Defaults).
    nonisolated static let leastIconSize: CGFloat = 64
    nonisolated static let largestIconSize: CGFloat = 128
    nonisolated static let nameRatio: CGFloat = 23 / 128

    var body: some View {
        GeometryReader { page in
            ScrollViewReader { scroller in
                ScrollView {
                    content
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            contentHeight = height
                            fit(page.size)
                        }
                        // Centered in the page however tall the window is (the
                        // user, 2026-10-31: "make it so it always stay
                        // centered"); a page too short for it scrolls, as before.
                        .frame(minHeight: page.size.height)
                }
                // The arrow keys' highlight scrolls into view, as on the other pages.
                .revealsKeyHighlight(with: scroller)
            }
            .onChange(of: page.size) { fit(page.size) }
        }
    }

    /// Fits the icon, and the name with it, to the page's room.
    private func fit(_ page: CGSize) {
        let fitted = Self.fittedIconSize(current: iconSize, page: page, content: contentHeight, name: nameSize)
        if abs(fitted - iconSize) >= 1 { iconSize = fitted }
    }

    /// The icon's side that makes the page as tall as `page` (its room
    /// shared by the icon and the name, whose height follows it), within
    /// `leastIconSize`…`largestIconSize`, the name kept on one line.
    /// Nothing measured yet: `current`.
    nonisolated static func fittedIconSize(current: CGFloat, page: CGSize, content: CGFloat, name: CGSize) -> CGFloat {
        guard current > 0, content > 0, name.width > 0, name.height > 0 else { return current }
        let fixed = content - current - name.height
        let byHeight = (page.height - fixed) / (1 + name.height / current)
        let byName = (page.width - 2 * 20) * current / name.width
        return max(leastIconSize, min(byHeight, byName, largestIconSize)).rounded(.down)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
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
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { nameSize = $0 }
            if let version = model.fullVersion {
                Text(verbatim: AutoHushText.version(version))
                    .foregroundStyle(.appSecondary)
                    .textSelection(.enabled)
            }
            // The README's tagline (the user, 2026-10-31).
            Text("Whatever’s playing steps aside when something else needs your ears.",
                 comment: "Settings → About, beside the app's icon and name: what AutoHush does, as the README's tagline says it: the media player's playback (music, podcasts, videos) pauses while another app plays sound")
                .foregroundStyle(.appSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
