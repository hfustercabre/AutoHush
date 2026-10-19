import os

/// A value a test shares with closures and other tasks, behind a lock: a
/// fake's log, a switch the test flips while the code under test reads it.
/// One type for them all, so none is a hand-made `@unchecked Sendable` box.
package final class Locked<Value: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<Value>

    package init(_ value: Value) {
        state = OSAllocatedUnfairLock(initialState: value)
    }

    package var value: Value {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// Reads and changes the value at once, as one step.
    package func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try state.withLockUnchecked(body)
    }

    package func append<Element>(_ element: Element) where Value == [Element] {
        state.withLockUnchecked { $0.append(element) }
    }
}

extension Locked where Value: Numeric {
    /// Adds one, as a count.
    package func increment() {
        state.withLock { $0 += 1 }
    }
}
