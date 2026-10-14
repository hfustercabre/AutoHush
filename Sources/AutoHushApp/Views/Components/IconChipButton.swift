import SwiftUI

/// A small chip showing a symbol, beside a heading or a pop-up: the Apps
/// tab's order and search, and the music players' search. Its label is what
/// VoiceOver says and, without a `help` of its own, its tooltip.
struct IconChipButton: View {
    let symbol: String
    let label: Text
    var help: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.appCaption.weight(.semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(ChipButtonStyle(filled: true, cornerRadius: 6))
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}
