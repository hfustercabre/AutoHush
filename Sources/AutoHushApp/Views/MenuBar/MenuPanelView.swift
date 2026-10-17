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
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: middleHeight)
            VStack(spacing: 0) {
                line
                ForEach(sections.filter { $0.section == .toolbar }, id: \.index) { view(for: $0.section) }
            }
            .padding(.bottom, 5)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0; report() }
        }
        .font(.appBody)
        .frame(width: menuContentWidth)
    }

    private func report() {
        onHeight(topHeight + middleHeight + bottomHeight)
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
        case .card: StatusCardView(model: model)
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

/// "Ignored Apps": the apps switched off, folded under their row; unfolded,
/// a click on one stops ignoring it. It follows the switches under Playing
/// Now while the menu is open.
struct MenuIgnoredAppsView: View {
    let model: StatusMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { model.perform(.toggleIgnoredApps) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text("Ignored Apps", comment: "Menu item")
                    Spacer()
                    Text(verbatim: model.status.ignoredApps.count.formatted())
                        .foregroundStyle(.appSecondary)
                        .accessibilityHidden(true)
                    Image(systemName: model.showsIgnoredApps ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appSecondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(MenuRowButtonStyle())
            .accessibilityValue(model.showsIgnoredApps ? AccessibilityText.expanded : AccessibilityText.collapsed)
            if model.showsIgnoredApps {
                Text("Click an app to stop ignoring it", comment: "Hint atop the Ignored Apps submenu")
                    .captionStyle()
                    .padding(.horizontal, 32)
                    .transition(.opacity)
                ForEach(model.status.ignoredApps, id: \.self) { app in
                    Button { model.perform(.setIgnored(app, false)) } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: AppIcon.image(for: app, players: model.status.playerOptions, size: 18))
                                .resizable()
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                            Text(verbatim: app.name).lineLimit(1)
                        }
                        .padding(.leading, 24)
                    }
                    .buttonStyle(MenuRowButtonStyle())
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(width: menuContentWidth)
    }
}
