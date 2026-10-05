import AppKit
import SwiftUI

/// Settings → About: the app's icon, name and version, what it does and the
/// players it works with, links to the project, a way to support it, and the
/// copyright. The menu's About button opens it.
///
/// Every gap between those parts shows the same 24 points. A part's own edge
/// adds to the space around it (the icon's transparent margin, a text's line
/// spacing), so each padding is the gap minus that edge, measured on the
/// rendered tab.
struct AboutSettingsView: View {
    let model: SettingsModel

    /// The space that shows between parts.
    private static let gap: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "AutoHush")
                .font(.appLargeTitle)
                .padding(.top, Self.gap - 13)
            if let version = model.fullVersion {
                Text("Version \(version)", comment: "Settings → About and Diagnostics; %@ is AutoHush's version")
                    .foregroundStyle(.appSecondary)
                    .textSelection(.enabled)
                    .padding(.top, Self.gap - 7.5)
            }
            VStack(spacing: 6) {
                Text("Pauses your music while other apps play audio, and resumes it afterwards.",
                     comment: "Settings → About: what AutoHush does")
                Text("Works with \(players).",
                     comment: "Settings → About; %@ lists the music players it works with, e.g. “Spotify, Apple Music and TIDAL”")
                    .foregroundStyle(.appSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.top, Self.gap - 3.5)
            HStack(spacing: 8) {
                link(Text(verbatim: "GitHub"), symbol: "chevron.left.forwardslash.chevron.right", to: ProjectInfo.homepage)
                link(Text("What's New", comment: "Settings → About: opens the release notes on GitHub"),
                     symbol: "sparkles", to: ProjectInfo.whatsNewPage(for: model.currentVersion.flatMap(AppVersion.init)))
                link(Text("Report an Issue", comment: "Settings → About: opens a new issue on GitHub"),
                     symbol: "ladybug", to: ProjectInfo.newIssuePage)
            }
            .padding(.top, Self.gap)
            VStack(spacing: 4) {
                Label {
                    Text("Would you like to support me?",
                         comment: "Settings → About and → General, before the Buy me a coffee link")
                } icon: {
                    Image(systemName: "cup.and.saucer")
                }
                .foregroundStyle(.appSecondary)
                Link(destination: ProjectInfo.supportPage) {
                    Text("Buy me a coffee",
                         comment: "Link to the developer's Buy Me a Coffee page (Settings → About and → General)")
                }
            }
            .font(.appCallout)
            .padding(.top, Self.gap - 2)
            if let copyright = Self.copyright {
                Text(verbatim: copyright)
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
                    .padding(.top, Self.gap - 3)
            }
        }
        .padding(.bottom, 8)
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Every player AutoHush works with, e.g. "Spotify, Apple Music and TIDAL".
    private var players: String {
        model.playerOptions.map(\.name).formatted(.list(type: .and))
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
