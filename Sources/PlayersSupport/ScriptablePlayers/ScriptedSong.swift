import AppKit
import Foundation
import AutoHushKit

/// Where an app says by AppleScript what it plays: its `current track`'s
/// name, else a property of its own naming it (VLC's `name of current
/// item`). It stays while paused, where a window's title may not, and it's
/// read wherever its window is. Player Check's panel trial tells the app's
/// row in the Now Playing panel by it, and so does AutoHush's `PanelWay`.
package enum ScriptedSong: Codable, Equatable, Sendable {
    /// `name of current track` (pnam of pTrk).
    case currentTrack
    /// A property of the app's own, by code.
    case property(String)

    /// Where `dictionary` names what it plays; `nil` when it doesn't.
    package init?(dictionary: ScriptingDictionary) {
        guard dictionary.namesItsSong else { return nil }
        if dictionary.hasCurrentTrack {
            self = .currentTrack
        } else if let code = dictionary.currentItemName {
            self = .property(code)
        } else {
            return nil
        }
    }

    /// What the app running as `pid` plays, by Apple event, waiting `timeout`
    /// at most; `nil` without Automation for it (it's never asked for here:
    /// no prompt), when it doesn't answer, or with nothing loaded. Blocks.
    package func read(pid: pid_t, timeout: TimeInterval = 1) -> String? {
        guard AutomationPermission(status: AutomationPermission.check(pid: pid, ask: false)) == .allowed else { return nil }
        let app = NSAppleEventDescriptor.null()
        let specifier = switch self {
        case .currentTrack: ScriptedAppPlayer.propertySpecifier("pnam", of: ScriptedAppPlayer.propertySpecifier("pTrk", of: app))
        case .property(let code): ScriptedAppPlayer.propertySpecifier(code, of: app)
        }
        let event = ScriptedAppPlayer.makeGetDataEvent(specifier, processIdentifier: pid)
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout),
              ScriptablePlayer.replyError(reply) == nil else { return nil }
        return reply.paramDescriptor(forKeyword: ScriptablePlayer.Code.directObject)?.stringValue
    }
}
