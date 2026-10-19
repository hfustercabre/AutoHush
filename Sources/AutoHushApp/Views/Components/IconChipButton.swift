import SwiftUI

/// A small chip showing a symbol, beside a heading or a pop-up: Settings →
/// Sound Sources' arrow that reverses the order, and its magnifier. Its
/// label is what VoiceOver says and, without a `help` of its own, its
/// tooltip.
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
        .buttonStyle(ChipButtonStyle(filled: true))
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}
