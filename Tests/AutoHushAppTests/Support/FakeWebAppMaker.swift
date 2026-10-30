import Foundation
import os
import AutoHushKit
import AutoHushTestSupport
@testable import AutoHushApp

/// Makes a web app in memory: reports the steps, then `onMake` puts it in place.
/// What the test sets and reads is behind a lock: a make runs on the
/// global executor meanwhile.
final class FakeWebAppMaker: WebAppMaking, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<MadeWebApp, WebAppMakingError>
    private var _onMake: @Sendable () -> Void = {}
    private var _waitsForCancel = false
    private var _wasCancelled = false

    var result: Result<MadeWebApp, WebAppMakingError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
    var onMake: @Sendable () -> Void {
        get { lock.withLock { _onMake } }
        set { lock.withLock { _onMake = newValue } }
    }
    /// Once the address is checked, waits until it's cancelled.
    var waitsForCancel: Bool {
        get { lock.withLock { _waitsForCancel } }
        set { lock.withLock { _waitsForCancel = newValue } }
    }
    var wasCancelled: Bool { lock.withLock { _wasCancelled } }

    init(_ result: Result<MadeWebApp, WebAppMakingError>) {
        _result = result
    }

    func makeWebApp(from address: String, onStep: @escaping @Sendable (WebAppMakingStep) -> Void,
                    confirmAdd: @escaping @Sendable () async -> Bool) async throws -> MadeWebApp {
        let made = try result.get()
        onStep(.checked)
        if waitsForCancel {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            lock.withLock { _wasCancelled = true }
            throw CancellationError()
        }
        onStep(.opened)
        if !made.alreadyThere {
            onStep(.readyToAdd(site: address))
            guard await confirmAdd() else { throw CancellationError() }
            onStep(.adding)
            onMake()
        }
        onStep(.made(made))
        return made
    }
}
