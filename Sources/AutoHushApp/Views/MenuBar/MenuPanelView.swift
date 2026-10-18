import SwiftUI
import AutoHushKit

/// Everything the menu shows, in `StatusMenuModel.sections`' order: the
/// card, the media player (its players unfolding under it), a warning and
/// its fix, Turn off for, Playing Now and Recently Played, Ignored Apps
/// (folding), the settings, the update found, and the buttons. As in
/// macOS's own menu bar menus (Wi-Fi's), the card and the buttons stay put
/// and only what's between them scrolls, between lines, when the panel is
/// taller than the screen (P1, the user's pick, 2026-10-18). It folds and
/// unfolds its parts in `MenuPanelView.animation`, the panel's height
/// following (`MenuPanel`); it reports its height to the panel (`onHeight`).
/// While more is below what shows, the last rows fade out over a small
/// chevron (C4, the user's pick, 2026-10-18; the chevron alone before macOS 26).
struct MenuPanelView: View {
    let model: StatusMenuModel
    /// Detection's, Fades' and Advanced's settings, as Settings changes them.
    let settings: SettingsModel?
    let onHeight: @MainActor (CGFloat) -> Void

    /// How its parts fold and unfold: smooth, no bounce, as the panel's
    /// height follows.
    static let animation = Animation.smooth(duration: MenuPanel.resizeDuration)

    /// The heights of the card (and the line under it), of what scrolls,
    /// and of the buttons (and the line over them): the panel's is their sum.
    @State private var topHeight: CGFloat = 0
    @State private var middleHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    /// How far down the middle shows, while it's taller than the screen
    /// leaves (`nil` while all of it shows).
    @State private var reach: ScrollReach?
    private var moreBelow: Bool { reach?.moreBelow ?? false }
    /// How tall the rows' fade is at the bottom edge while more is below.
    static let fadeHeight: CGFloat = 32
    /// The rows fade only from macOS 26: before, the mask takes their
    /// vibrancy, every row dimmer while it's on (measured on 14.4 and 15,
    /// 2026-10-18), so the chevron alone says more is below.
    static var fadesRows: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    private var sections: [(index: Int, section: MenuSection)] {
        model.sections.enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(sections.filter { $0.section == .card }, id: \.index) { view(for: $0.section) }
                line
            }
            .padding(.top, 5)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0; report() }
            ScrollView {
                VStack(spacing: 0) {
                    let middle = sections.filter { $0.section != .card && $0.section != .toolbar }
                    ForEach(middle, id: \.index) { part in
                        if part.index != middle.first?.index, needsLine(before: part.section, at: part.index) { line }
                        view(for: part.section)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { middleHeight = $0; report() }
                .background { MoreBelowReader.contentFrame }
                // The rows themselves fade out at the bottom edge, so the
                // menu's own material shows through (the user, 2026-10-18).
                .mask(alignment: .top) { fadeMask }
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .modifier(MoreBelowReader(reach: $reach))
            .overlay(alignment: .bottom) {
                if moreBelow { moreBelowChevron.transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.15), value: moreBelow)
            // It fills what the panel leaves between the card and the
            // buttons, as the panel's height follows the content's: sized
            // to its content, the parts shorter than a shrinking panel were
            // centered in it, and dropped for a moment as a part folded.
            .frame(idealHeight: middleHeight, maxHeight: .infinity)
            VStack(spacing: 0) {
                line
                ForEach(sections.filter { $0.section == .toolbar }, id: \.index) { view(for: $0.section) }
            }
            .padding(.bottom, 5)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0; report() }
        }
        .font(.appBody)
        .environment(\.isInMenu, true)
        .frame(width: menuContentWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func report() {
        onHeight(topHeight + middleHeight + bottomHeight)
    }

    /// The rows' mask: whole, but for their last `fadeHeight` above the
    /// bottom edge while more is below, which fades to clear. It's in the
    /// rows' own space (a mask on the scroll view doesn't reach AppKit's),
    /// so it moves with the scrolling to stay at the edge.
    @ViewBuilder private var fadeMask: some View {
        if let reach, reach.moreBelow, Self.fadesRows {
            VStack(spacing: 0) {
                Rectangle().frame(height: max(0, reach.visibleBottom - Self.fadeHeight))
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fadeHeight)
                Spacer(minLength: 0)
            }
        } else {
            Rectangle()
        }
    }

    /// A small chevron at the bottom edge, over the fading rows: there's
    /// more below.
    private var moreBelowChevron: some View {
        Image(systemName: "chevron.compact.down")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.appSecondary)
            .padding(.bottom, 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true) // VoiceOver reaches the rows below by itself
    }

    /// A line between the parts, where the menu had its separators.
    private func needsLine(before section: MenuSection, at index: Int) -> Bool {
        let previous = index > 0 ? model.sections[index - 1] : nil
        switch section {
        case .warning, .reopenAutoHush, .snooze, .playingNow: return true
        case .recentlyPlayed: return previous != .playingNow
        case .ignoredApps, .settings, .update: return true
        default: return false
        }
    }

    private var line: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 4)
    }

    @ViewBuilder private func view(for section: MenuSection) -> some View {
        switch section {
        case .card: StatusCardView(model: model, settings: settings)
        case .mediaPlayer: MenuMediaPlayerView(model: model)
        case .warning(let permission):
            actionRow(permission.grantTitle, symbol: "exclamationmark.triangle.fill", .resolveWarning(permission))
        case .reopenAutoHush:
            actionRow(PermissionText.reopen, symbol: "exclamationmark.triangle.fill", .reopenAutoHush)
        case .useAntiDot:
            actionRow(PermissionText.useAntiDot, symbol: nil, .useAntiDotMode)
        case .snooze: SnoozeBarView(model: model)
        case .playingNow: PlayingAppsView(model: model, list: .playingNow)
        case .recentlyPlayed: PlayingAppsView(model: model, list: .recentlyPlayed)
        case .ignoredApps: MenuIgnoredAppsView(model: model)
        case .settings:
            if let settings { MenuSettingsView(model: model, settings: settings) }
        case .update: updateRow
        case .toolbar: MenuToolbarView(model: model)
        }
    }

    /// A row that acts, as the menu's own rows did: a warning (with its
    /// symbol) and its fix.
    private func actionRow(_ title: String, symbol: String?, _ command: StatusMenuCommand) -> some View {
        Button { model.perform(command) } label: {
            HStack(spacing: 8) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(.appWarning)
                            .accessibilityLabel(Text("Warning", comment: "VoiceOver label: this menu item needs attention"))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 18)
                Text(verbatim: title)
            }
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(.horizontal, 8)
    }

    /// "Install AutoHush 0.3.8…", which shows the update found; while it
    /// installs, a greyed-out "Installing…".
    @ViewBuilder private var updateRow: some View {
        if let offer = model.status.updateOffer {
            let version = offer.release.version.description
            let installing = offer.state == .installing
            Button { model.perform(.showUpdate) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .frame(width: 18)
                        .accessibilityLabel(Text("Update", comment: "VoiceOver label of the update icon"))
                    Text(verbatim: installing
                         ? String(localized: "Installing AutoHush \(version)…", comment: "Menu item, greyed out while an update installs; %@ is its version")
                         : String(localized: "Install AutoHush \(version)…", comment: "Menu item: shows the update found; %@ is its version"))
                }
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(installing)
            .padding(.horizontal, 8)
        }
    }
}

/// "Ignored Apps": the apps switched off (V5, the user's pick, 2026-10-18),
/// as the settings' parts: the title over a row with up to three of their
/// icons, their names and what they are, and a chevron; unfolded, the apps
/// under it, a click on one stops ignoring it. It follows the switches under
/// Playing Now while the menu is open.
struct MenuIgnoredAppsView: View {
    let model: StatusMenuModel

    private var apps: [AudioSource] { model.status.ignoredApps }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuPartTitle(Text("Ignored Apps", comment: "The menu: heading over the apps that don’t pause your player"))
            MenuFoldingRow(title: Self.names(of: apps.map(\.name)),
                           subtitle: String(localized: "They don’t pause your player.", comment: "The menu, under the names of the ignored apps"),
                           leadingWidth: apps.count > 1 ? 32 : 22, isOpen: model.showsIgnoredApps,
                           action: { model.perform(.toggleIgnoredApps) }) {
                iconStack
            }
            if model.showsIgnoredApps {
                ForEach(apps, id: \.self) { app in
                    Button { model.perform(.setIgnored(app, false)) } label: {
                        HStack(spacing: 8) {
                            icon(app)
                            Text(verbatim: app.name).lineLimit(1)
                        }
                        .padding(.leading, 24)
                    }
                    .buttonStyle(MenuRowButtonStyle())
                    .help(Text("Click an app to stop ignoring it", comment: "The menu: the tooltip of each ignored app, unfolded under Ignored Apps"))
                    .padding(.horizontal, 8)
                    .transition(.opacity)
                }
            }
        }
        .frame(width: menuContentWidth)
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
    private var iconStack: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(apps.prefix(3).enumerated()), id: \.offset) { index, app in
                icon(app).offset(x: CGFloat(index) * 7)
            }
        }
    }
}

/// How far down a scroll view's content shows.
struct ScrollReach: Equatable {
    /// The bottom edge of what shows, in the content's own space.
    var visibleBottom: CGFloat
    var contentHeight: CGFloat
    var moreBelow: Bool { visibleBottom < contentHeight - 1 }
}

/// How far down a scroll view's content shows: from macOS 15 by its scroll
/// geometry; on macOS 14 by where its content is in it.
private struct MoreBelowReader: ViewModifier {
    @Binding var reach: ScrollReach?
    @State private var height: CGFloat = 0
    @State private var contentFrame: CGRect = .zero

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ScrollReach.self) { geometry in
                ScrollReach(visibleBottom: geometry.contentOffset.y + geometry.containerSize.height,
                            contentHeight: geometry.contentSize.height)
            } action: { _, new in reach = new }
        } else {
            content
                .coordinateSpace(.named(Self.space))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0; update() }
                .onPreferenceChange(ContentFrame.self) { frame in
                    MainActor.assumeIsolated { contentFrame = frame ?? .zero; update() }
                }
        }
    }

    private func update() {
        reach = ScrollReach(visibleBottom: height - contentFrame.minY, contentHeight: contentFrame.height)
    }

    static let space = "menuScroll"

    /// Behind the scrolled content: where it is (macOS 14 only reads it).
    static var contentFrame: some View {
        GeometryReader { Color.clear.preference(key: ContentFrame.self, value: $0.frame(in: .named(space))) }
    }

    /// Where the scrolled content is, in the scroll view's own space. Views
    /// that don't set it give `nil`, which mustn't replace the frame (macOS
    /// 14 reduces them in after it: measured on 14.4, 2026-10-18).
    struct ContentFrame: PreferenceKey {
        static let defaultValue: CGRect? = nil
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
    }
}
