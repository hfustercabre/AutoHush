import Testing
@testable import AutoHushApp

@Suite("MenuRowButtonStyle")
struct MenuRowButtonStyleTests {
    @Test("in the menu, a row lights up only where the keys' highlight is: the arrow keys leave no second lit row under the pointer")
    func oneLitRow() {
        // The pointer rests on the row; ↓ moves the highlight to the next.
        #expect(!MenuRowButtonStyle.isLit(enabled: true, tinted: false, hovered: true, highlighted: false, followsKeys: true))
        #expect(MenuRowButtonStyle.isLit(enabled: true, tinted: false, hovered: false, highlighted: true, followsKeys: true))
        // Without the keys' highlight, the pointer lights it.
        #expect(MenuRowButtonStyle.isLit(enabled: true, tinted: false, hovered: true, highlighted: false, followsKeys: false))
        // Disabled, or tinted by the menu behind it: never itself.
        #expect(!MenuRowButtonStyle.isLit(enabled: false, tinted: false, hovered: true, highlighted: true, followsKeys: true))
        #expect(!MenuRowButtonStyle.isLit(enabled: true, tinted: true, hovered: true, highlighted: true, followsKeys: true))
    }
}
