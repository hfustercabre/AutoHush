import SwiftUI

/// A row of the menu or a side window that acts when clicked, as a menu's
/// item: its picture in the rows' picture column, then its text. In the menu
/// (`Place.menu`: the warnings, Use AntiDot Mode Instead, the update found)
/// it lights up in the accent color itself, as a menu item, its picture
/// where the other rows' are (`MenuSpacing.row`); in a side window
/// (`Place.sideWindow`: the players, Add an App…, Add a Web App…, Ignore
/// Another App…) the menu's tint shows behind it instead (the user,
/// 2026-10-18), from the window's margin. Return or Space presses it while
/// it's highlighted. In the menu, one with a second line (`twoLines`) takes
/// the tint instead of the accent color (D2c, `MenuRowButtonStyle`).
struct MenuActionRow<Picture: View, Content: View>: View {
    enum Place { case menu, sideWindow }

    var place = Place.menu
    /// Its picture column and the gap after it: those of the rows around it.
    var layout = MenuSpacing.row
    /// Its content has a second line, in grey (D2c).
    var twoLines = false
    let action: () -> Void
    let picture: Picture
    let content: Content

    init(place: Place = .menu, layout: MenuSpacing.RowLayout = MenuSpacing.row, twoLines: Bool = false,
         action: @escaping () -> Void, @ViewBuilder picture: () -> Picture, @ViewBuilder content: () -> Content) {
        self.place = place
        self.layout = layout
        self.twoLines = twoLines
        self.action = action
        self.picture = picture()
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: layout.gap) {
                picture.frame(width: layout.picture)
                content
            }
        }
        .buttonStyle(MenuRowButtonStyle(tinted: place == .sideWindow, twoLines: twoLines))
        .modifier(HighlightableControl(cornerRadius: 6, lightsItself: place == .menu, press: action))
        // The row's own 6 pt inside (`MenuRowButtonStyle`): in the menu, out
        // from the rows' leading; in a side window, into its margin.
        .padding(.leading, place == .menu ? layout.leading - 6 : -6)
        .padding(.trailing, place == .menu ? 8 : -6)
    }
}
