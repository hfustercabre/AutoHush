import SwiftUI

/// A search field in the style of the chips: a magnifier, the text, and a ✕
/// that closes the search (`onClose`) or, without one, clears what was typed.
/// Settings → Sound Sources and the places that offer the media players use it.
/// With `results`, VoiceOver hears them once typing pauses. With Increase
/// Contrast, outlined 1 pt, as AutoHush's other faint fills (D5a, the a11y
/// audit's D5, the user's pick, 2026-11-06: its fill alone barely showed).
/// Its closures are passed by their labels, never as a trailing closure,
/// which Swift gives the first of them (`onClick`): Sound Sources' close
/// was a click's from 2026-10-18, so its ✕ only cleared and a click in
/// the field closed the search (K3-1, the full check, 2026-11-06).
struct SearchField: View {
    @Binding var text: String
    /// Takes the keyboard focus as it appears, in a window (not in a menu:
    /// `StatusMenuController` gives it the keyboard there, `focusRequest`).
    var focusesOnAppear = false
    /// Takes the focus each time this changes (the menu's side window, once
    /// it's key).
    var focusRequest = 0
    /// What the search found, for VoiceOver; `nil` while there's nothing
    /// to tell (the list still loading).
    var results: SearchResults?
    /// A click in it, before it takes the focus (the menu's side window
    /// becomes key then).
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    /// Return in it (which a window's main button then doesn't get).
    var onSubmit: (() -> Void)?
    /// ↑ and ↓ in it, for a list under it whose selection they move (-1, 1).
    var onMove: ((Int) -> Void)?
    /// ← in it while it's empty (with text, it moves the caret): the menu's
    /// side window closes, as ← closes it from its rows (with VoiceOver on,
    /// the field has the keyboard from the start; 2026-11-06).
    var onLeftWhileEmpty: (() -> Void)?
    @FocusState private var isFocused: Bool

    /// How long typing pauses before VoiceOver hears the results: not over
    /// each key's echo.
    static let resultsDelay = Duration.milliseconds(500)
    /// The ✕'s hit area's side (D6a).
    static let clearHitSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            // The prompt is the placeholder, which goes as one types. The
            // label alone draws as a placeholder only outside a form: in a
            // grouped Form (Sound Sources' heading) macOS drew it as a row
            // label in front of the text, "Search  vl" (K3-2, the full
            // check, 2026-11-06). The label stays, hidden, for VoiceOver.
            TextField(text: $text, prompt: Text("Search", comment: "A search field's placeholder")) {
                Text("Search", comment: "A search field's placeholder")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .simultaneousGesture(TapGesture().onEnded { onClick?() })
            .onSubmit { onSubmit?() }
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.leftArrow) {
                guard text.isEmpty, let onLeftWhileEmpty else { return .ignored }
                onLeftWhileEmpty()
                return .handled
            }
            if let onClose {
                clearButton(Text("Close search", comment: "The button that closes a search"), action: onClose)
            } else if !text.isEmpty {
                clearButton(Text("Clear search", comment: "The button that empties a search field")) { text = "" }
            }
        }
        .font(.appCallout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).tinted(.chipFill, outline: .appSecondary))
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

    /// The ✕, as it looks, in a 24 × 24 pt hit area (D6a, the a11y audit's
    /// D6, the user's pick, 2026-11-06: the symbol alone, about 13 pt, was
    /// under WCAG 2.5.8's 24 pt), 3 pt further from the text; out of the
    /// field's layout above, below and into its trailing margin, so the
    /// field keeps its size.
    private func clearButton(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.appSecondary)
                .frame(width: Self.clearHitSize, height: Self.clearHitSize)
                .contentShape(Rectangle())
                .padding(.vertical, -6)
                .padding(.leading, 3)
                .padding(.trailing, -6)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
