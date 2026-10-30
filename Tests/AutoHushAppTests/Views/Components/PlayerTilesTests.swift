import AppKit
import CoreGraphics
import SwiftUI
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

    @Test("five rows are five tiles tall with the gaps between them, so a sixth row scrolls, wherever among the groups it falls")
    func fiveRows() {
        #expect(PlayerTiles.height(ofRows: 0).isZero)
        #expect(PlayerTiles.height(ofRows: 1).isEqual(to: PlayerTiles.tileHeight))
        let fiveRows = 5 * PlayerTiles.tileHeight + 4 * PlayerTiles.rowSpacing
        // isEqual(to:): #expect's own `==` on CGFloats fails here even when they're equal.
        #expect(PlayerTiles.height(ofRows: 5).isEqual(to: fiveRows))
        #expect(PlayerChooserView.visibleTileRows == 5)

        // The groups' rows and where their tiles start: the list cuts off a
        // little under the last row shown, in whichever group it is.
        let groups: [(rows: Int, top: CGFloat)] = [(rows: 2, top: 30), (rows: 1, top: 150), (rows: 3, top: 230)]
        func cut(_ rows: Int, content: CGFloat = 500) -> CGFloat {
            PlayerTiles.visibleHeight(rows: rows, groups: groups, contentHeight: content)
        }
        let under = PlayerTiles.rowSpacing + 12
        #expect(cut(5).isEqual(to: 230 + PlayerTiles.height(ofRows: 2) + under)) // two of the third group's
        #expect(cut(3).isEqual(to: 150 + PlayerTiles.height(ofRows: 1) + under)) // the second group's last
        #expect(cut(1).isEqual(to: 30 + PlayerTiles.height(ofRows: 1) + under))
        #expect(cut(6).isEqual(to: 500)) // every row: all of them
        #expect(cut(5, content: 300).isEqual(to: 300)) // never more than they are
        #expect(cut(5, content: 0).isZero) // not measured yet
    }

    @Test("in the welcome window, a search keeps the tiles' card as tall as it was before, however few tiles it leaves")
    func searchKeepsHeight() async {
        let apps = (1...18).map { PlayerOption(bundleID: "com.example.player\($0)", name: "Player \($0)",
                                              appURL: URL(fileURLWithPath: "/Applications/Player \($0).app")) }
        func tiles(_ options: [PlayerOption], search: String = "", rows: Int = PlayerChooserView.visibleTileRows) -> PlayerTiles {
            PlayerTiles(options: options, selection: nil, onSelect: { _ in }, onAddWebApp: {},
                        maxVisibleRows: rows, holdsHeight: !search.isEmpty, search: search)
        }
        func hosting(_ tiles: PlayerTiles) -> NSHostingView<PlayerTiles> {
            let hosting = NSHostingView(rootView: tiles)
            hosting.frame = NSRect(x: 0, y: 0, width: PlayerChooserView.width, height: 1200)
            return hosting
        }
        let all = await settledHeight(hosting(tiles(apps, rows: 20)))
        let welcome = hosting(tiles(apps))
        let shown = await settledHeight(welcome)
        #expect(shown < all) // more rows than show: they scroll
        welcome.rootView = tiles(apps.filter { $0.name == "Player 7" }, search: "Player 7")
        let searched = await settledHeight(welcome)
        #expect(searched.isEqual(to: shown), "\(searched) after the search, \(shown) before")
    }

    /// `hosting`'s height once it stops changing: the tiles' measures come
    /// back a layout later.
    private func settledHeight(_ hosting: NSView) async -> CGFloat {
        var last: CGFloat = -1
        var same = 0
        for _ in 0..<100 where same < 3 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
            let height = hosting.fittingSize.height
            same = height == last ? same + 1 : 0
            last = height
        }
        return last
    }
}
