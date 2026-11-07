/// A state observer a `BackedUpPlayer` tells when its own way's
/// permission goes missing or comes back, held weakly: one let go of is
/// told nothing.
struct WeakStateObserver: Sendable {
    weak var observer: BackedUpStateObserver?
}
