import SwiftUI

/// A row that only counts with the switch above it on, as a part of it:
/// indented beside a thin line (D3, the user's pick, 2026-10-26: Stay
/// paused after calls under Resume playback).
struct DependentRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.quaternary)
                .frame(width: 2)
                .accessibilityHidden(true)
            content
        }
        .padding(.leading, 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}
