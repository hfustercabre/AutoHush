/// Where each web app's recipe is kept. A protocol, so tests keep theirs in
/// memory.
package protocol PlayPauseRecipeStore: Sendable {
    func recipe(for bundleID: String) -> PlayPauseRecipe?
    func save(_ recipe: PlayPauseRecipe, for bundleID: String)
    func forget(for bundleID: String)
}
