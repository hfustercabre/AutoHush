import AppKit
import os

/// Clicks in the player's own windows above ordinary ones while another app
/// is in front: its menu bar icon, the menu that opens from it, a floating
/// panel of its. A play or pause there is the user's, as input while the
/// player is in front is (`PlayerInput`; 2026-10-27: a menu bar player,
/// played from its icon, was taken for starting by itself and muted). A
/// click in one of its ordinary windows brings it forward, and isn't the
/// user's play: it may play its trailer again as it comes forward.
/// Read from a global monitor of mouse-downs, which needs no permission
/// (key events would), and the windows on screen: their owners and frames,
/// which need no Screen Recording.
///
/// `@unchecked Sendable`: `monitor` is set once, on the main thread, as it
/// starts, and only removed as it goes; the times are behind a lock.
package final class PlayerWindowClicks: @unchecked Sendable {
    private let times = OSAllocatedUnfairLock<[Date]>(initialState: [])
    /// Whether a process is the player's.
    private let isPlayer: @Sendable (pid_t) -> Bool
    private var monitor: Any?

    /// Watching the clicks in the windows of the app `bundleID`.
    package convenience init(bundleID: String) {
        self.init { NSRunningApplication.running(bundleID)?.processIdentifier == $0 }
        let start: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                    guard let location = event.cgEvent?.location else { return }
                    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
                    self?.take(at: location, windows: windows, date: Date())
                }
            }
        }
        if Thread.isMainThread { start() } else { DispatchQueue.main.async(execute: start) }
    }

    /// Not watching: tests hand it their clicks (`take`).
    init(isPlayer: @escaping @Sendable (pid_t) -> Bool) {
        self.isPlayer = isPlayer
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// A mouse-down at `location` (global coordinates, from the top left),
    /// `windows` listed front to back as `CGWindowListCopyWindowInfo` does:
    /// kept when the window under it is the player's and above ordinary
    /// windows (layer 0), for `spanMemory`.
    func take(at location: CGPoint, windows: [[String: Any]], date: Date) {
        guard let window = Self.window(at: location, in: windows), window.layer != 0, isPlayer(window.owner) else { return }
        times.withLock { times in
            times.removeAll { $0 < date.addingTimeInterval(-PlayerInput.spanMemory) }
            times.append(date)
        }
    }

    /// Whether the user clicked in one of the player's windows after `date`.
    func since(_ date: Date) -> Bool {
        times.withLock { $0.contains { $0 > date } }
    }

    /// The frontmost window under `point` that can be seen (not fully
    /// transparent): the process owning it, and its layer.
    static func window(at point: CGPoint, in windows: [[String: Any]]) -> (owner: pid_t, layer: Int)? {
        for window in windows {
            guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.contains(point) else { continue }
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            return (owner, (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0)
        }
        return nil
    }
}
