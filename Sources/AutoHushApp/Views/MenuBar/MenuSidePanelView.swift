import SwiftUI
import AutoHushKit

/// The side window beside the menu (W2, the user's pick, 2026-10-18), as a
/// submenu: Media Player's players under their title (`MenuPlayerListView`),
/// or the ignored apps under theirs, each with its switch (`SourceSwitchRow`).
/// It scrolls when it's taller than the screen leaves; it reports its
/// height to its window (`onHeight`).
struct MenuSidePanelView: View {
    let model: StatusMenuModel
    let onHeight: @MainActor (CGFloat) -> Void

    static let width: CGFloat = 300

    var body: some View {
        ScrollViewReader { scroller in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.openSide {
                case .players?:
                    MenuPartTitle(Text(verbatim: MenuMediaPlayerView.title))
                        .padding(.bottom, 4)
                    MenuPlayerListView(model: model)
                        .padding(.horizontal, 14)
                case .ignoredApps?:
                    MenuPartTitle(Text(verbatim: MenuIgnoredAppsView.title))
                        .padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.listedIgnoredApps, id: \.self) { source in
                            SourceSwitchRow(model: model, source: source, saysIgnoredShortly: true)
                        }
                        // Several at once (the user, 2026-10-18); the menu closes for the panel.
                        Button { model.perform(.ignoreAnotherApp) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                    .frame(width: 20)
                                    .accessibilityHidden(true)
                                Text(verbatim: IgnoreAppsPicker.title)
                            }
                        }
                        .buttonStyle(MenuRowButtonStyle(tinted: true))
                        .modifier(HighlightableControl(cornerRadius: 6, press: { model.perform(.ignoreAnotherApp) }))
                        .padding(.horizontal, -6)
                    }
                    .padding(.horizontal, 14)
                case nil:
                    EmptyView()
                }
            }
            .padding(.vertical, 8)
            .frame(width: Self.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: model.sideKeyboard.revealed) { _, revealed in
            if let revealed { scroller.scrollTo(revealed) }
        }
        }
        .font(.appBody)
        .environment(\.isInMenu, true)
        .environment(model.sideKeyboard)
        .environment(\.controlActiveState, .key)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
