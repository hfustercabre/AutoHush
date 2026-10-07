import SwiftUI

/// Settings → General's search over the music players, opened by the
/// magnifier beside their pop-up: the players whose names match, as the
/// pop-up offers them; a click on an installed one chooses it, and on a
/// suggested web app opens "Add a Web App".
struct PlayerSearchPopover: View {
    let options: [PlayerOption]
    /// The chosen player's bundle ID, checked in the list.
    let chosen: String?
    let choose: (String) -> Void
    @State private var search = ""

    var body: some View {
        let shown = options.matching(search)
        VStack(alignment: .leading, spacing: 8) {
            SearchField(text: $search, focusesOnAppear: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if shown.isEmpty {
                        Text(verbatim: PlayerOption.noMatchNote(search))
                            .foregroundStyle(.appSecondary)
                            .padding(6)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, option in
                        if index == shown.webAppsStart {
                            WebAppsHeading()
                                .padding(.horizontal, 6)
                                .padding(.top, index == 0 ? 0 : 6)
                        }
                        row(for: option)
                    }
                }
            }
            .frame(height: 300) // the same whatever matches, so it doesn't jump as you type
        }
        .font(.appBody)
        .padding(12)
        .frame(width: 280)
    }

    /// A check on the chosen player, then its icon and name, and "Not
    /// installed" under one that isn't.
    private func row(for option: PlayerOption) -> some View {
        Button { choose(option.bundleID) } label: {
            HStack(spacing: 8) {
                // Where menus put it: the pop-up beside offers the same players.
                Image(systemName: "checkmark")
                    .font(.appCaption.weight(.bold))
                    .frame(width: 12)
                    .opacity(option.bundleID == chosen ? 1 : 0)
                    .accessibilityHidden(true)
                Image(nsImage: option.icon(size: 20))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                RowTitle(Text(verbatim: option.name),
                         subtitle: option.isInstalled ? nil : Text(PlayerOption.notInstalledLabel),
                         badge: option.isUntested ? PlayerOption.untestedBadge : nil)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipButtonStyle(cornerRadius: 6)) // which dims it while disabled
        .disabled(!option.isClickable)
        .accessibilityAddTraits(option.bundleID == chosen ? .isSelected : [])
    }
}
