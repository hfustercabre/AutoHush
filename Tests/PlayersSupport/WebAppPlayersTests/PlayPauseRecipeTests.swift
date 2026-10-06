import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers

@Suite("PlayPauseRecipe")
struct PlayPauseRecipeTests {
    private let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Places.playerBar])

    @Test("the button's words tell the state")
    func state() {
        #expect(recipe.state(of: PageButton(handle: ButtonHandle(1), label: "Pause")) == .playing)
        #expect(recipe.state(of: PageButton(handle: ButtonHandle(1), label: "Play")) == .paused)
        #expect(recipe.state(of: PageButton(handle: ButtonHandle(1), label: "Play Mix")) == nil)
    }

    @Test("it's found at its place, the nearest to its distance from the bottom; never elsewhere")
    func find() {
        let places: [Int: ButtonPlace] = [
            1: Places.main,
            2: ButtonPlace(path: Places.playerBar.path, distanceFromBottom: 90),
            3: ButtonPlace(path: Places.playerBar.path, distanceFromBottom: 45),
            4: Places.playerBar,
        ]
        let buttons = [
            PageButton(handle: ButtonHandle(1), label: "Play"),
            PageButton(handle: ButtonHandle(2), label: "Play"),
            PageButton(handle: ButtonHandle(3), label: "Pause"),
            PageButton(handle: ButtonHandle(4), label: "Shuffle"),
        ]
        let place = { (handle: ButtonHandle) in places[handle.element.base as! Int] }
        #expect(recipe.find(in: buttons, place: place)?.handle == ButtonHandle(3))
        #expect(recipe.find(in: [buttons[0], buttons[3]], place: place) == nil)
    }

    @Test("learning again with the same words adds the place; other words replace it")
    func merging() {
        let fullScreen = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Places.fullScreen])
        #expect(recipe.merging(fullScreen).places == [Places.fullScreen, Places.playerBar])
        #expect(recipe.merging(recipe).places == [Places.playerBar])
        let many = (0..<5).reduce(recipe) { kept, number in
            kept.merging(PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause",
                                         places: [ButtonPlace(path: ["\(number)"], distanceFromBottom: 1)]))
        }
        #expect(many.places.count == PlayPauseRecipe.placeLimit)
        #expect(many.places.first?.path == ["4"])
        let spanish = PlayPauseRecipe(playLabel: "Reproducir", pauseLabel: "Pausar", places: [Places.main])
        #expect(recipe.merging(spanish) == spanish)
    }

    @Test("it's kept as a property list")
    func storage() {
        let stored = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Places.playerBar, Places.main])
        #expect(PlayPauseRecipe(propertyList: stored.propertyList) == stored)
        #expect(PlayPauseRecipe(propertyList: ["play": "Play"]) == nil)
    }
}
