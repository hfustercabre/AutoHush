import SwiftUI

/// One choice among a few, as a row of chips; the chosen one is filled with
/// the accent color.
struct ChoiceChips<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    onSelect(option.value)
                } label: {
                    Text(verbatim: option.title)
                        .font(.appCallout)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: option.value == selection))
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
