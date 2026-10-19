extension Array where Element: Equatable {
    /// The element `step` places from `current` (← -1, → 1), kept within
    /// the list: a choice the arrow keys step through stops at its ends.
    /// `nil` when `current` isn't in it.
    func stepping(from current: Element, by step: Int) -> Element? {
        guard let index = firstIndex(of: current) else { return nil }
        return self[Swift.min(Swift.max(index + step, 0), count - 1)]
    }
}
