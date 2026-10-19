/// Holds whoever waits on it until it's opened; open, it lets everyone
/// through until it's closed again. A test holds the code under test at a
/// step with it, however busy the machine.
package actor Gate {
    private var isOpen: Bool
    private var held: [CheckedContinuation<Void, Never>] = []

    /// Closed: it holds whoever waits.
    package init() {
        isOpen = false
    }

    package init(open: Bool) {
        isOpen = open
    }

    /// How many wait at it now.
    package var waiting: Int { held.count }

    package func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { held.append($0) }
    }

    /// Lets those waiting go, and every later one at once.
    package func open() {
        isOpen = true
        held.forEach { $0.resume() }
        held = []
    }

    /// Holds the next ones again.
    package func close() {
        isOpen = false
    }
}
