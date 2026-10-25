import SwiftUI
import AutoHushKit

/// Everything the menu shows, in `StatusMenuModel.sections`' order: the
/// card (its Change Player row opening the players in a side window), a
/// warning and its fix, Turn off for, Playing Now and Recently Played,
/// Ignored Apps (its side window), the update found, and the buttons. As in
/// macOS's own menu bar menus (Wi-Fi's), the card and the buttons stay put
/// and only what's between them scrolls, between lines, when the panel is
/// taller than the screen (P1, the user's pick, 2026-10-18). It reports its
/// height to the panel (`onHeight`), which follows it (`MenuPanel`).
/// While more is below what shows, the last rows fade out over a small
/// chevron (`MenuScrollArea`).
struct MenuPanelView: View {
    let model: StatusMenuModel
    /// The card's checks, as Settings shows them.
    let settings: SettingsModel?
    let onHeight: @MainActor (CGFloat) -> Void

    /// The heights of the card (and the line under it), of what scrolls,
    /// and of the buttons (and the line over them): the panel's is their sum.
    @State private var topHeight: CGFloat = 0
    @State private var middleHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0

    private var sections: [(index: Int, section: MenuSection)] {
        model.sections.enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        let sections = sections
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(sections.filter { $0.section == .card }, id: \.section.id) { view(for: $0.section) }
                MenuLine()
            }
            .padding(.top, 5)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0; report() }
            // The arrow keys go through it before what scrolls.
            .environment(\.highlightBand, .top)
            MenuScrollArea(isCapped: model.isCappedByScreen, revealed: model.keyboard.revealed,
                           onHeight: { middleHeight = $0; report() }) {
                VStack(spacing: 0) {
                    let middle = sections.filter { $0.section != .card && $0.section != .toolbar }
                    // Identified by what they are: one that comes leaves the others be.
                    ForEach(middle, id: \.section.id) { part in
                        if part.index != middle.first?.index, needsLine(before: part.section, at: part.index) { MenuLine() }
                        view(for: part.section)
                    }
                }
            }
            // It fills what the panel leaves between the card and the
            // buttons, as the panel's height follows the content's: sized
            // to its content, the parts shorter than a shrinking panel were
            // centered in it, and dropped for a moment as a part folded.
            .frame(idealHeight: middleHeight, maxHeight: .infinity)
            VStack(spacing: 0) {
                MenuLine()
                ForEach(sections.filter { $0.section == .toolbar }, id: \.section.id) { view(for: $0.section) }
            }
            .padding(.bottom, 5)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0; report() }
            // The arrow keys go through it after what scrolls, whatever is scrolled.
            .environment(\.highlightBand, .bottom)
        }
        .font(.appBody)
        .environment(\.isInMenu, true)
        .environment(model.keyboard)
        // Drawn active while its side window has the keyboard, as a menu
        // with a submenu open is. (`controlActiveState` is soft-deprecated
        // for `appearsActive`, macOS 15 on: kept while 14.4 is supported,
        // 2026-10-18.)
        .environment(\.controlActiveState, .key)
        .frame(width: menuContentWidth)
        .frame(maxHeight: .infinity, alignment: .top)
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
        case .ignoredApps, .update: return true
        default: return false
        }
    }

    /// A part of the menu, telling where the pointer goes: onto another part
    /// than the open side window's, that one closes.
    private func view(for section: MenuSection) -> some View {
        part(section)
            .contentShape(Rectangle())
            .onHover { if $0 { model.perform(.pointerEntered(section)) } }
    }

    @ViewBuilder private func part(_ section: MenuSection) -> some View {
        switch section {
        case .card: StatusCardView(model: model, settings: settings)
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
        case .update: updateRow
        case .toolbar: MenuToolbarView(model: model)
        case .playerRow: EmptyView() // inside the card
        }
    }

    /// A row that acts, as the menu's own rows did: a warning (with its
    /// symbol) and its fix.
    private func actionRow(_ title: String, symbol: String?, _ command: StatusMenuCommand) -> some View {
        MenuActionRow(action: { model.perform(command) }) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.appWarning)
                    .accessibilityLabel(Text("Warning", comment: "VoiceOver label: this menu item needs attention"))
            } else {
                Color.clear
            }
        } content: {
            Text(verbatim: title)
        }
    }

    /// "Install AutoHush 0.3.8…", which shows the update found; while it
    /// installs, a greyed-out "Installing…".
    @ViewBuilder private var updateRow: some View {
        if let offer = model.status.updateOffer {
            let version = offer.release.version.description
            let installing = offer.state == .installing
            MenuActionRow(action: { model.perform(.showUpdate) }) {
                Image(systemName: "arrow.down.circle")
                    .accessibilityLabel(Text("Update", comment: "VoiceOver label of the update icon"))
            } content: {
                // Only what this copy can do: one that can't install itself
                // tells where to get it (the workflow audit, 2026-10-22).
                Text(verbatim: installing
                     ? String(localized: "Installing AutoHush \(version)…", comment: "Menu item, greyed out while an update installs; %@ is its version")
                     : !offer.canInstall
                     ? String(localized: "AutoHush \(version) Is Available…", comment: "Menu item: shows the update found, for a copy that can't install it itself (its alert says where to get it); %@ is its version")
                     : String(localized: "Install AutoHush \(version)…", comment: "Menu item: shows the update found; %@ is its version"))
            }
            .disabled(installing)
        }
    }
}
