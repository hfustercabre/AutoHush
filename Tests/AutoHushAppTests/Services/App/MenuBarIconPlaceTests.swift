import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// On defaults of its own, never the user's.
@Suite("MenuBarIconPlace")
@MainActor
struct MenuBarIconPlaceTests {
    private let defaults: UserDefaults = MemoryDefaults()
    private var place: MenuBarIconPlace { MenuBarIconPlace(defaults: defaults) }
    private var position: Double? { defaults.object(forKey: MenuBarIconPlace.positionKey) as? Double }

    @Test("the first time, the icon goes beside the system's icons, and only that time")
    func placedOnce() {
        place.prepare()
        #expect(position == MenuBarIconPlace.nearSystemIcons)
        defaults.set(400.0, forKey: MenuBarIconPlace.positionKey) // the user ⌘-drags it
        place.prepare()
        #expect(position == 400)
    }

    @Test("an icon the user placed before stays where it is")
    func userPlaceKept() {
        defaults.set(250.0, forKey: MenuBarIconPlace.positionKey)
        place.prepare()
        #expect(position == 250)
    }

    @Test("kept beside the system's icons, it goes back there at each launch")
    func keptThere() {
        defaults.set(250.0, forKey: MenuBarIconPlace.positionKey)
        place.keepsNearSystemIcons = true
        place.prepare()
        #expect(position == MenuBarIconPlace.nearSystemIcons)
        #expect(MenuBarIconPlace(defaults: defaults).keepsNearSystemIcons)
    }
}
