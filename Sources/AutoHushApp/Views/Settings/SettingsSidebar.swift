import SwiftUI

/// Settings' sidebar: its pages, a row each with its symbol on a square
/// tinted with the accent color, in groups, each under its name and what
/// it's for (S5d, the user's pick, 2026-10-25); the page shown on a grey
/// background. At its foot, AutoHush's name and version, and a way to
/// support it.
struct SettingsSidebar: View {
    let model: SettingsModel
    let navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 { Spacer().frame(height: 14) }
                        if let title = group.title { heading(title, note: group.note) }
                        ForEach(group.pages, id: \.self) { row($0) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            SettingsSidebarFoot(model: model)
        }
    }

    /// A group's name, and what it's for under it, in grey.
    private func heading(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.appSecondary)
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(verbatim: note)
                    .font(.appCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.leading, 10)
        .padding(.bottom, 4)
    }

    private func row(_ page: SettingsPage) -> some View {
        let isShown = navigation.page == page
        return Button { navigation.page = page } label: {
            HStack(spacing: 12) {
                SymbolTile(symbol: page.symbol)
                Text(verbatim: page.title)
                    .font(.appSidebarRow)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isShown { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.sidebarSelectionFill) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The arrow keys and the pointer highlight it; ↑ and ↓ show its page at once.
        .modifier(Highlightable(cornerRadius: 10, press: { navigation.page = page },
                                isCurrent: { navigation.page == page }))
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}

/// The sidebar's foot, under a line: AutoHush's name and version, then the
/// way to support it. About has the rest.
struct SettingsSidebarFoot: View {
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(verbatim: "AutoHush").font(.appSidebarName)
                if let version = model.currentVersion {
                    Text(verbatim: AutoHushText.version(version))
                        .font(.appCaption)
                        .foregroundStyle(.appSecondary)
                }
            }
            SupportLine()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 16) }
    }
}
