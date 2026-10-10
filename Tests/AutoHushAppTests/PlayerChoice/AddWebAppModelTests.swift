import AutoHushKit
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

    @Test("Safari's dialog closed without adding is said under Add to Dock until it's opened again")
    func closedWithoutAdding() {
        let model = readyModel(attempt: 1)
        model.apply(.adding)
        model.apply(.notAdded)
        model.apply(.readyToAdd(site: "play.qobuz.com"))
        #expect(model.closedWithoutAdding)
        let ready = AddWebAppView.steps(for: model.phase, closedWithoutAdding: model.closedWithoutAdding, learning: nil)
        #expect(ready.last { $0.button == .addToDock }?.warning != nil)
        model.apply(.adding)
        #expect(!model.closedWithoutAdding)
        let adding = AddWebAppView.steps(for: model.phase, learning: nil)
        #expect(adding.first { $0.state == .current }?.notes.count == 1) // rename it there, then Add
        model.apply(.notAdded)
        model.reset()
        #expect(!model.closedWithoutAdding)
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

    @Test("a service with a site per country: the Mac's country at first, a pick puts its site in the address")
    func countrySites() {
        let sites = CountrySites(name: "Some Music",
                                 byRegion: ["ES": "music.some.es", "GB": "music.some.co.uk", "IE": "music.some.co.uk",
                                            "US": "music.some.com"],
                                 elsewhere: "music.some.com")
        let model = AddWebAppModel()
        model.countrySites = [sites]
        model.region = "ES"
        model.reset(address: "music.some.es")
        #expect(model.addressSites == sites)
        #expect(model.country(in: sites) == "ES")
        model.chooseCountry("IE", in: sites)
        #expect(model.address == "music.some.co.uk")
        #expect(model.country(in: sites) == "IE") // not the United Kingdom, which shares it
        model.chooseCountry("", in: sites)
        #expect(model.address == "music.some.com")
        #expect(model.country(in: sites) == "") // Other Countries, not the United States
        model.address = "play.qobuz.com"
        #expect(model.addressSites == nil) // no countries for another site
        model.reset(address: "music.some.co.uk")
        #expect(model.country(in: sites) == "GB") // the pick is forgotten
        // Once it's being added, the country stays.
        model.continueTapped()
        model.chooseCountry("ES", in: sites)
        #expect(model.address == "music.some.co.uk")
        // Every country with its own site is offered, once.
        let countries = model.countries(of: sites)
        #expect(countries.map(\.code).sorted() == ["ES", "GB", "IE", "US"])
        #expect(countries.map(\.name) == countries.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(model.countries(of: sites) == countries) // worked out once
    }
}
