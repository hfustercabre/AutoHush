import SwiftUI

/// A small chip under the menu card's status line, with its symbol: Retry,
/// Reopen and Unmute (`PlayerFixButtons`).
struct CardChip: View {
    let title: Text
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { title } icon: { Image(systemName: symbol) }
                .font(.appCallout)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .buttonStyle(ChipButtonStyle(filled: true))
        .padding(.top, 4)
    }
}
