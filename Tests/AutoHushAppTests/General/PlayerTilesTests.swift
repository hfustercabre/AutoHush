import Testing
@testable import AutoHushApp

@Suite("PlayerTiles")
@MainActor
struct PlayerTilesTests {
    @Test("tiles go three a row; the add tile counts in the web apps' rows")
    func rows() {
        #expect(PlayerTiles.rowCount(0) == 0)
        #expect(PlayerTiles.rowCount(3) == 1)
        #expect(PlayerTiles.rowCount(4) == 2)
        #expect(PlayerTiles.rowCount(5 + 1) == 2) // five web apps and the add tile
    }

    @Test("five rows are five tiles tall with the gaps between them, so a sixth row scrolls")
    func fiveRows() {
        #expect(PlayerTiles.height(ofRows: 0).isZero)
        #expect(PlayerTiles.height(ofRows: 1).isEqual(to: PlayerTiles.tileHeight))
        let fiveRows = 5 * PlayerTiles.tileHeight + 4 * PlayerTiles.rowSpacing
        // isEqual(to:): #expect's own `==` on CGFloats fails here even when they're equal.
        #expect(PlayerTiles.height(ofRows: 5).isEqual(to: fiveRows))
        #expect(PlayerChooserView.visibleTileRows == 5)
    }
}
