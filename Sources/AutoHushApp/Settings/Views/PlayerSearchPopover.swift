import SwiftUI

/// Settings → General's search over the music players, opened by the
/// magnifier beside their pop-up: the players whose names match, installed
/// first; a click on an installed one chooses it.
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
                    ForEach(shown) { row(for: $0) }
                }
            }
            .frame(height: 300) // the same whatever matches, so it doesn't jump as you type
        }
        .font(.appBody)
        .padding(12)
        .frame(width: 280)
    }

    /// The player's icon and name, "Not installed" under one that isn't, and
    /// a check on the chosen one.
    private func row(for option: PlayerOption) -> some View {
        Button { choose(option.bundleID) } label: {
            HStack(spacing: 8) {
                Image(nsImage: option.icon(size: 20))
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                RowTitle(Text(verbatim: option.name),
                         subtitle: option.isInstalled ? nil : Text(PlayerOption.notInstalledLabel))
                Spacer(minLength: 8)
                if option.bundleID == chosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChipButtonStyle(cornerRadius: 6)) // which dims it while disabled
        .disabled(!option.isInstalled)
        .accessibilityAddTraits(option.bundleID == chosen ? .isSelected : [])
    }
}
