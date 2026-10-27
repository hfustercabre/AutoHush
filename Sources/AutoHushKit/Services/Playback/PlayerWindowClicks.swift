import AppKit
import os

/// Clicks in the player's own windows while another app is in front: its
/// menu bar icon, the menu that opens from it, a panel of its that doesn't
/// come forward. A play or pause there is the user's, as input while the
/// player is in front is (`PlayerInput`; 2026-10-27: MacMusicPlayer, played
/// from its menu bar icon, was taken for starting by itself and muted).
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
        self.init { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier == bundleID }
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
    /// kept when the window under it is the player's, for `spanMemory`.
    func take(at location: CGPoint, windows: [[String: Any]], date: Date) {
        guard let owner = Self.owner(at: location, in: windows), isPlayer(owner) else { return }
        times.withLock { times in
            times.removeAll { $0 < date.addingTimeInterval(-PlayerInput.spanMemory) }
            times.append(date)
        }
    }

    /// Whether the user clicked in one of the player's windows after `date`.
    func since(_ date: Date) -> Bool {
        times.withLock { $0.contains { $0 > date } }
    }

    /// The process owning the frontmost window under `point` that can be
    /// seen (not fully transparent).
    static func owner(at point: CGPoint, in windows: [[String: Any]]) -> pid_t? {
        for window in windows {
            guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.contains(point) else { continue }
            return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        }
        return nil
    }
}
