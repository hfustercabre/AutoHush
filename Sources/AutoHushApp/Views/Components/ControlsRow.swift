import SwiftUI

/// A web app's controls, in the menu's card and Settings → General: whether
/// they're learned, and Learn Controls (Learn Again once learned), which
/// opens a new learning window from the first step.
struct ControlsRow: View {
    let name: String
    let isLearned: Bool
    /// The button's text: the menu's are a step smaller than Settings'.
    var buttonFont: Font = .appBody
    let learn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(Text(verbatim: LearnText.controlsTitle),
                     subtitle: Text(verbatim: isLearned ? LearnText.learnedNote : LearnText.notLearnedNote(name)))
            Spacer(minLength: 8)
            Button(action: learn) {
                Text(verbatim: isLearned ? LearnText.learnAgainButton : LearnText.learnButton).font(buttonFont)
            }
            .buttonStyle(.chip)
            .fixedSize()
        }
    }
}
