import SwiftUI

/// Under the menu's card while AutoHush learns the chosen web app's
/// controls: what to do, ticked as it's seen. The learning window shows the
/// same; this is for when it was closed.
struct LearningCardView: View {
    let model: StatusMenuModel

    var body: some View {
        if let hasPlayed = model.status.learningHasPlayed {
            Card(padding: 10) {
                LearningSummary(name: model.status.playerName, hasPlayed: hasPlayed,
                                deadline: model.status.learningPauseDeadline, note: model.status.learningNote,
                                pauseMode: model.status.learningPauseMode, action: { model.perform(.learningStep($0)) })
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(width: menuContentWidth)
        }
    }
}
