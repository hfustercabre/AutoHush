/// One of playercheck's one-line answers, a tab between fields: the helper
/// writes it with its `line`, and AutoHush and the Player Check app read it
/// with its `init?(line:)`, so neither side can drift.
package protocol OneLineAnswer: Equatable, Sendable {
    /// The answer as the helper writes it.
    var line: String { get }

    /// The answer a line gives; `nil` for a line that isn't one.
    init?(line: some StringProtocol)
}

extension OneLineAnswer {
    /// A line's fields: split at each tab, empty ones kept, so a field's
    /// place never shifts.
    static func fields(of line: some StringProtocol) -> [String] {
        String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
}
