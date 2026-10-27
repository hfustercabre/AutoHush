import AppKit
import SwiftUI

/// Settings → About, A4 (the user's pick, 2026-10-26: "its too crowded"
/// once Updates came here): the app's icon beside its name, version and what
/// it does; its updates (`UpdatesCard`, a page of their own until W1, the
/// user, 2026-10-25); links to the project; the copyright. It fits the
/// window without scrolling. The players it works with are on the Media
/// Player page, and the way to support it at the sidebar's foot. The menu's
/// About button opens it.
struct AboutSettingsView: View {
    let model: SettingsModel

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity)
            }
            // The arrow keys' highlight scrolls into view, as on the other pages.
            .revealsKeyHighlight(with: scroller)
        }
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

    /// The icon beside the name and version, and what AutoHush does.
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "AutoHush")
                        .font(.appAboutTitle)
                    if let version = model.fullVersion {
                        Text("Version \(version)", comment: "Settings → About, Settings' sidebar and Diagnostics; %@ is AutoHush's version")
                            .foregroundStyle(.appSecondary)
                            .textSelection(.enabled)
                    }
                }
                Text("Pauses what’s playing while other apps play audio, and resumes it afterwards.",
                     comment: "Settings → About, beside the app's icon and name: what AutoHush does")
                    .foregroundStyle(.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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
