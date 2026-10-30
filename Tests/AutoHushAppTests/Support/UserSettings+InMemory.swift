import Foundation
import AutoHushKit
@testable import AutoHushApp
import AutoHushTestSupport

extension UserSettings {
    /// The user's settings as in-memory preferences hold them.
    static func inMemory() -> UserSettings {
        UserSettings(preferences: Preferences(store: InMemoryPreferenceStore()))
    }
}
