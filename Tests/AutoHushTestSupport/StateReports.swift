import AutoHushKit

/// What a `MockMusicPlayer`'s observer reports to, once made.
@MainActor
package final class StateReports {
    var onChange: (@MainActor (PlayerState) -> Void)?
    nonisolated init() {}
}
