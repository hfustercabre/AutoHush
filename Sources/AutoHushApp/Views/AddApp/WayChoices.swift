import SwiftUI
import CheckedPlayers

/// The last step when ways worked (U2, the user's pick, 2026-10-15): each one
/// AutoHush can use as a card to choose, the recommended first and chosen
/// until another is, and under them, dimmed, those that didn't work or can't
/// be used (the panel only its sound tells, in AntiDot mode), with why.
struct WayChoices: View {
    let model: AddAppModel
    let result: CheckResult
    let app: String

    var body: some View {
        let choosable = model.choosableWays
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(choosable.enumerated()), id: \.element) { index, kind in
                if let way = result.ways.first(where: { $0.kind == kind }) { card(way, recommended: index == 0) }
            }
            ForEach(result.ways.filter { !choosable.contains($0.kind) }, id: \.kind) { way in
                WayRow(way: way, app: app, windowsClosed: result.windowsClosed, panelNeedsSound: model.panelNeedsSound).opacity(0.6).padding(.horizontal, 9).padding(.top, 2)
            }
        }
    }

    private func card(_ way: CheckResult.WayResult, recommended: Bool) -> some View {
        let isChosen = model.chosenWay == way.kind
        let row = WayRow(way: way, app: app, windowsClosed: result.windowsClosed, recommended: recommended, panelNeedsSound: model.panelNeedsSound, inCard: true)
        return Button { model.choose(way.kind) } label: {
            row
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .chosenOutline(isChosen, outlinedOtherwise: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        // The row's words and value, on the button alone: said once.
        .accessibilityLabel(Text(verbatim: row.accessibilityWords))
        .accessibilityValue(Text(verbatim: row.accessibilityValue))
    }
}
