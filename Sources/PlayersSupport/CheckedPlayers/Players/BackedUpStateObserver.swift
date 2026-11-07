import AutoHushKit

/// A `BackedUpPlayer`'s state observer: its own player's, and a polled one
/// of its backups' state that runs only while its own way's permission is
/// missing (`denied`), started and stopped as that changes
/// (`followDenial`). A player whose own way is allowed, nearly always,
/// polls nothing (2026-11-06: each one woke once a second before).
@MainActor
final class BackedUpStateObserver: PlayerStateObserving {
    private let own: any PlayerStateObserving
    private let backups: PolledStateObserver
    private let denied: @Sendable () -> Bool
    private var observing = false
    /// Its backups' state is polled now.
    private(set) var pollsBackups = false

    init(own: any PlayerStateObserving, backups: PolledStateObserver, denied: @escaping @Sendable () -> Bool) {
        self.own = own
        self.backups = backups
        self.denied = denied
    }

    func start() {
        observing = true
        own.start()
        followDenial()
    }

    func stop() {
        observing = false
        own.stop()
        followDenial()
    }

    /// Its backups polled only while it observes and its own way's
    /// permission is missing; each start reports their state afresh, since
    /// a stop forgets the last one (`PolledStateObserver.stop`).
    func followDenial() {
        pollsBackups = observing && denied()
        if pollsBackups { backups.start() } else { backups.stop() }
    }
}

/// A state observer a `BackedUpPlayer` tells when its own way's
/// permission goes missing or comes back, held weakly: one let go of is
/// told nothing.
struct WeakStateObserver: Sendable {
    weak var observer: BackedUpStateObserver?
}
