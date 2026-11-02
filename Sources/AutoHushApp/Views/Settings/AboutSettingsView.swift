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
    /// The icon fitted to the page, the name with it (`AboutFit`), from
    /// where the last opening left it.
    @State private var fit = AboutFit(resuming: Self.lastFit)
    /// Where About's fit was last, in this run only (not kept on disk): the
    /// next opening starts there, not at 96 pt, so the icon doesn't jump as
    /// the page opens (I1, the user, 2026-11-01). Tests set it, to draw
    /// the compact header.
    static var lastFit: AboutFit?

    /// The icon's side beside the name.
    nonisolated static let compactIconSize: CGFloat = 56
    /// The name's size beside `compactIconSize`: 17 pt, as under a 96 pt icon.
    private static let compactNameFont = Font.appAboutTitle(iconSize: 96)

    var body: some View {
        GeometryReader { page in
            ScrollViewReader { scroller in
                ScrollView {
                    content
                        .padding(AboutFit.pageMargin)
                        .frame(maxWidth: .infinity)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            update { $0.contentMeasured(height: height) }
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
                update { $0.pageChanged(to: page.size) }
            }
        }
    }

    /// Changes the fit, and remembers it for the next opening.
    private func update(_ change: (inout AboutFit) -> Void) {
        change(&fit)
        Self.lastFit = fit
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            if fit.isCompact { compactHeader } else { header }
            UpdatesCard(model: model)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                // Help in GitHub's place (T7b-swap, the user's pick, 2026-11-02):
                // it opens the README on GitHub, and a fourth chip doesn't fit
                // the narrowest window.
                link(Text(verbatim: ButtonText.help), symbol: "questionmark.circle", to: ProjectInfo.helpPage)
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
    /// pick, 2026-10-31), the icon and the name sized by the fit.
    private var header: some View {
        VStack(spacing: 6) {
            icon(side: fit.iconSize)
            name(.appAboutTitle(iconSize: fit.iconSize))
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                    update { $0.nameMeasured(size) }
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
                icon(side: Self.compactIconSize)
                VStack(alignment: .leading, spacing: 2) {
                    name(Self.compactNameFont)
                    version
                }
            }
            tagline
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// AutoHush's icon, `side` points square; the name beside it says it to
    /// VoiceOver.
    private func icon(side: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    /// AutoHush's name, on one line.
    private func name(_ font: Font) -> some View {
        Text(verbatim: "AutoHush")
            .font(font)
            .fixedSize()
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
