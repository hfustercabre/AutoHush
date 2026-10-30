/// A value that never tells two otherwise equal values apart: a
/// synthesized `==` skips it, so a new property can't be missed by a
/// hand-written one (a player's placeholder icon, `PlayerOption`).
@propertyWrapper
struct EqualityIgnored<Value>: Equatable {
    var wrappedValue: Value

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}
