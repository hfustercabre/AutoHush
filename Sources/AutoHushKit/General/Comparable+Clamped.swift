extension Comparable {
    /// The value, limited to `range`.
    package func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
