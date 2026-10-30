import Foundation
import AutoHushKit
@testable import AutoHushApp
import AutoHushTestSupport

extension PlayerSession {
    /// A session with no player chosen, whose monitorings are stand-ins.
    static func noPlayer(settings: UserSettings = .inMemory()) -> PlayerSession {
        PlayerSession(player: nil, players: MusicPlayerCatalog(players: []),
                      preferences: Preferences(store: InMemoryPreferenceStore()),
                      settings: settings.state.monitoring, makeMonitoring: FakeMonitorings().make,
                      locateApp: { _ in nil })
    }
}
