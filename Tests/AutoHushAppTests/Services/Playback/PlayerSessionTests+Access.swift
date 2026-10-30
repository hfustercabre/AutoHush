import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

extension PlayerSessionTests {
    // MARK: - Checking access while it runs

    @MainActor
    @Test("access is checked again when another app starts playing, and a permission taken away starts over")
    func lostPermissionNoticedWhenOthersPlay() async {
        let bench = Bench()
        let session = await bench.started()
        let monitoring = bench.monitorings.made[0]

        monitoring.send(.activeSources([Self.viewer]))
        await TestWait.until { await bench.first.verifyCallCount == 2 }
        // Still playing: not checked again.
        monitoring.send(.activeSources([Self.safari, Self.viewer]))
        await session.waitUntilIdle()
        #expect(await bench.first.verifyCallCount == 2)
        #expect(session.state.health == .ready)

        monitoring.send(.activeSources([]))
        await bench.first.setFailVerify(MusicPlayerError.automationPermissionDenied)
        monitoring.send(.activeSources([Self.viewer]))
        await TestWait.until { session.state.health == .needsPermission(.automation(player: "First")) }
        #expect(monitoring.isStopped)
        #expect(session.state.activeSources.isEmpty)
    }

    @MainActor
    @Test("checking control access starts over only for a missing permission, and only while monitoring runs")
    func controlAccessCheck() async {
        let bench = Bench()
        let session = bench.makeSession(bench.first)
        session.checkAccess() // not monitoring yet
        await session.waitUntilIdle()
        #expect(await bench.first.verifyCallCount == 0)

        session.launch()
        await TestWait.until { session.state.health == .ready }
        for error: MusicPlayerError? in [nil, .playerNotRunning, .playerNotResponding] {
            await bench.first.setFailVerify(error)
            let calls = await bench.first.verifyCallCount
            session.checkAccess()
            await TestWait.until { await bench.first.verifyCallCount > calls }
            await session.waitUntilIdle()
        }
        #expect(session.state.health == .ready)
        #expect(!bench.monitorings.made[0].isStopped)

        await bench.first.setFailVerify(MusicPlayerError.accessibilityPermissionDenied)
        session.checkAccess()
        await TestWait.until { session.state.health == .needsPermission(.accessibility(player: "First")) }
        #expect(bench.monitorings.made[0].isStopped)
    }
}
