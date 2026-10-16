/// What's kept of an app's page button between runs, per app: its
/// `ButtonPath`, and, once learned as AutoHush learns a web app's, its
/// recipe (`SavedRecipe`), which finds it again after its page reloads;
/// and the text of its row in the Now Playing panel, once a press of it
/// changed the app.
package struct SavedButton: Codable, Equatable, Sendable {
    package var path: ButtonPath?
    package var recipe: SavedRecipe?
    package var panelRow: String?

    package init(path: ButtonPath? = nil, recipe: SavedRecipe? = nil, panelRow: String? = nil) {
        self.path = path
        self.recipe = recipe
        self.panelRow = panelRow
    }
}
