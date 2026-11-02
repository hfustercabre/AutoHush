import SwiftUI

/// A search field in the style of the chips: a magnifier, the text, and a ✕
/// that closes the search (`onClose`) or, without one, clears what was typed.
/// Settings → Sound Sources and the places that offer the media players use it.
/// With `results`, VoiceOver hears them once typing pauses.
struct SearchField: View {
    @Binding var text: String
    /// Takes the keyboard focus as it appears, in a window (not in a menu:
    /// `StatusMenuController` gives it the keyboard there, `focusRequest`).
    var focusesOnAppear = false
    /// Takes the focus each time this changes (the menu's side window, once
    /// it's key).
    var focusRequest = 0
    /// What the search found, for VoiceOver; `nil` while there's nothing
    /// to tell (the list still loading). Before the closures, so Sound
    /// Sources' trailing closure binds as it did.
    var results: SearchResults?
    /// A click in it, before it takes the focus (the menu's side window
    /// becomes key then).
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    /// Return in it (which a window's main button then doesn't get).
    var onSubmit: (() -> Void)?
    /// ↑ and ↓ in it, for a list under it whose selection they move (-1, 1).
    var onMove: ((Int) -> Void)?
    @FocusState private var isFocused: Bool

    /// How long typing pauses before VoiceOver hears the results: not over
    /// each key's echo.
    static let resultsDelay = Duration.milliseconds(500)

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
            .simultaneousGesture(TapGesture().onEnded { onClick?() })
            .onSubmit { onSubmit?() }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            if let onClose {
                clearButton(Text("Close search", comment: "The button that closes a search"), action: onClose)
            } else if !text.isEmpty {
                clearButton(Text("Clear search", comment: "The button that empties a search field")) { text = "" }
            }
        }
        .font(.appCallout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.chipFill))
        // Once it's shown: a popover's field doesn't take it any sooner. In
        // the view's own task, which ends with the view: a focus set once
        // the view was gone crashed macOS's focus system (CI, 2026-11-01).
        .task {
            guard focusesOnAppear else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isFocused = true
        }
        .onChange(of: focusRequest) { isFocused = true }
        // Each key starts the wait again; low priority, after what VoiceOver
        // is saying (A14, 2026-11-01).
        .task(id: text) {
            guard let results, !text.isEmpty else { return }
            guard (try? await Task.sleep(for: Self.resultsDelay)) != nil else { return }
            postAnnouncement(results.announcement, priority: .low)
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let onMove else { return .ignored }
        onMove(step)
        return .handled
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
