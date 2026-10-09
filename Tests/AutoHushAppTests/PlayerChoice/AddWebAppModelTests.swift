import Foundation
import Testing
@testable import AutoHushApp

@MainActor
@Suite("AddWebAppModel", .timeLimit(.minutes(1)))
struct AddWebAppModelTests {
    /// A model showing `site` ready to add, for the add numbered `attempt`.
    private func readyModel(attempt: Int) -> AddWebAppModel {
        let model = AddWebAppModel()
        model.address = "play.qobuz.com"
        model.attempt = attempt
        model.continueTapped()
        model.apply(.readyToAdd(site: "play.qobuz.com"))
        return model
    }

    @Test("Add to Dock ends the wait with yes; starting over ends it with no")
    func addAndReset() async {
        let model = readyModel(attempt: 1)
        let added = Task { await model.waitForAdd(attempt: 1) }
        await Task.yield()
        model.addTapped()
        #expect(await added.value)

        let other = readyModel(attempt: 2)
        let reset = Task { await other.waitForAdd(attempt: 2) }
        await Task.yield()
        other.reset()
        #expect(await reset.value == false)
    }

    @Test("a cancelled add's late cancel doesn't end a newer add's wait")
    func lateCancelSparesNewerAdd() async {
        let model = readyModel(attempt: 1)
        let first = Task { await model.waitForAdd(attempt: 1) }
        await Task.yield()
        // The first add is cancelled, and a new one waits before the cancel arrives.
        model.attempt = 2
        let second = Task { await model.waitForAdd(attempt: 2) }
        #expect(await first.value == false) // a newer wait ends the older one
        model.cancelWait(attempt: 1)        // the first add's cancel, late
        var finished = false
        let watcher = Task { _ = await second.value; finished = true }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!finished) // still waiting for Add to Dock
        model.apply(.readyToAdd(site: "play.qobuz.com"))
        model.addTapped()
        #expect(await second.value)
        _ = await watcher.value
    }

    @Test("an add that's no longer the latest doesn't wait at all")
    func staleAddDoesNotWait() async {
        let model = readyModel(attempt: 3)
        #expect(await model.waitForAdd(attempt: 2) == false)
    }

    @Test("what isn't a web address is said with the catalog's example, or without one")
    func notAWebAddressNote() {
        let model = AddWebAppModel()
        model.fail(.notAWebAddress)
        #expect(model.problemText == "That isn't a web address.")
        model.exampleAddress = "music.example.com"
        #expect(model.problemText == "That isn't a web address. Try one like music.example.com.")
    }
}
