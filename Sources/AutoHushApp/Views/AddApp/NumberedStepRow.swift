import SwiftUI

/// A step of the Add an App window, numbered (W2): its number in a circle
/// while it's still to come (filled with the accent color while it's the
/// one to do), a check once done, a spinner while AutoHush does it, a cross
/// once it failed (`StepSymbol`); then its title, and its lines and buttons
/// under it. VoiceOver reads the title with its number ("Step 2 of 6, …").
struct NumberedStepRow<Content: View>: View {
    let number: Int
    /// How many steps there are.
    let count: Int
    let status: StepStatus
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // One width for every mark, so the titles line up.
            StepSymbol(status: status, number: number).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .fontWeight(status.state == .current ? .semibold : .regular)
                    .foregroundStyle(status.state == .done ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: AddAppText.stepLabel(number, of: count, title: title)))
                    .accessibilityValue(Text(verbatim: status.state.voiceOverValue))
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
