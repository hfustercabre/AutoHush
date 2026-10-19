import AutoHushTestSupport
import WebAppPlayers

/// The web apps' learned buttons, kept in memory by bundle ID.
package final class MemoryRecipeStore: PlayPauseRecipeStore {
    private let recipes: Locked<[String: PlayPauseRecipe]>

    package init(_ recipes: [String: PlayPauseRecipe] = [:]) {
        self.recipes = Locked(recipes)
    }

    package func recipe(for bundleID: String) -> PlayPauseRecipe? { recipes.value[bundleID] }
    package func save(_ recipe: PlayPauseRecipe, for bundleID: String) { recipes.withLock { $0[bundleID] = recipe } }
    package func forget(for bundleID: String) { recipes.withLock { $0[bundleID] = nil } }
}
