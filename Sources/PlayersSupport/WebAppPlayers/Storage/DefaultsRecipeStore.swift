import Foundation
import AutoHushKit

/// The recipes in AutoHush's preferences, by the web app's bundle ID. Read
/// and written from the players' own queues, each change under
/// `KeyedDefaults`' lock: another web app may be saving its own, or old ones
/// being cleared out, at the same time.
package struct DefaultsRecipeStore: PlayPauseRecipeStore {
    static let key = Preferences.webAppButtonsKey
    private let stored: KeyedDefaults

    /// `suiteName`: the preferences' suite; `nil` for AutoHush's own.
    package init(suiteName: String? = nil) {
        stored = KeyedDefaults(key: Self.key, suiteName: suiteName)
    }

    /// Kept in `defaults` (tests keep theirs in memory).
    package init(defaults: UserDefaults) {
        stored = KeyedDefaults(key: Self.key, defaults: defaults)
    }

    package func recipe(for bundleID: String) -> PlayPauseRecipe? {
        (stored.values()[bundleID] as? [String: Any]).flatMap(PlayPauseRecipe.init(propertyList:))
    }

    package func save(_ recipe: PlayPauseRecipe, for bundleID: String) {
        stored.set(recipe.propertyList, for: bundleID)
    }

    package func forget(for bundleID: String) {
        stored.set(nil, for: bundleID)
    }
}
