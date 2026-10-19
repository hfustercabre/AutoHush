import SwiftUI

/// Buttons side by side when they fit on one line each, else one under the
/// other (a step's, Settings → Detection's Audio Recording ones).
struct FlowingButtons<Content: View>: View {
    /// Between them side by side; one under the other, they're 6 pt apart.
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}
