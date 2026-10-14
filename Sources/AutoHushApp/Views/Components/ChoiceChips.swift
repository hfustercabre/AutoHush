import SwiftUI

/// One choice among a few, as a row of chips; the chosen one is filled with
/// the accent color. An option can be unavailable: dimmed and not chosen,
/// but a click on it is reported, so the view can say why.
struct ChoiceChips<Value: Hashable>: View {
    struct Option {
        let title: String
        let value: Value
        var isAvailable = true
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void
    /// A click on an unavailable option.
    var onUnavailableClick: () -> Void = {}
    /// Why an option is unavailable, for VoiceOver (sighted users see it dimmed).
    var unavailableNote: String?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    option.isAvailable ? onSelect(option.value) : onUnavailableClick()
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
                // A disabled group is dimmed already: once is enough.
                .opacity(option.isAvailable || !isEnabled ? 1 : 0.45)
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
                .accessibilityHint(option.isAvailable ? Text(verbatim: "") : Text(verbatim: unavailableNote ?? ""))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
