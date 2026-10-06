import SwiftUI

/// A search field in the style of the chips: a magnifier, the text, and a ✕
/// that closes the search (`onClose`) or, without one, clears what was typed.
/// Settings → Apps and the places that offer the music players use it.
struct SearchField: View {
    @Binding var text: String
    /// Takes the keyboard focus as it appears, in a window (not in a menu:
    /// `StatusMenuController` gives it the keyboard there).
    var focusesOnAppear = false
    var onClose: (() -> Void)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            TextField(text: $text) {
                Text("Search", comment: "A search field's placeholder")
            }
            .textFieldStyle(.plain)
            .focused($isFocused)
            if let onClose {
                clearButton(Text("Close Search", comment: "The button that closes a search"), action: onClose)
            } else if !text.isEmpty {
                clearButton(Text("Clear Search", comment: "The button that empties a search field")) { text = "" }
            }
        }
        .font(.appCallout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.chipFill))
        .onAppear {
            // Once it's shown: a popover's field doesn't take it any sooner.
            if focusesOnAppear { DispatchQueue.main.async { isFocused = true } }
        }
    }

    private func clearButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.appSecondary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
