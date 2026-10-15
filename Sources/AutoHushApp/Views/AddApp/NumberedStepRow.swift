import SwiftUI

/// A step of the Add an App window, numbered (W2): its number in a circle
/// while it's still to come (filled with the accent color while it's the
/// one to do), a check once done, a spinner while AutoHush does it, a cross
/// once it failed; then its title, and its lines and buttons under it.
/// VoiceOver reads the title with its number ("Step 2 of 6, …").
struct NumberedStepRow<Content: View>: View {
    let number: Int
    /// How many steps there are.
    let count: Int
    let mark: AddAppModel.Mark
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // One width for every mark, so the titles line up.
            symbol.frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .fontWeight(mark == .current || mark == .busy ? .semibold : .regular)
                    .foregroundStyle(mark == .done ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: AddAppText.stepLabel(number, of: count, title: title)))
                    .accessibilityValue(Text(verbatim: state.voiceOverValue))
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var symbol: some View {
        switch mark {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.appWarning)
        case .busy:
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        case .current: Image(systemName: "\(number).circle.fill").foregroundStyle(Color.accentColor)
        case .todo: Image(systemName: "\(number).circle").foregroundStyle(.appSecondary)
        }
    }

    /// As a checklist's steps say it to VoiceOver.
    private var state: StepState {
        switch mark {
        case .done: .done
        case .current, .busy: .current
        case .todo: .todo
        case .failed: .failed
        }
    }
}
