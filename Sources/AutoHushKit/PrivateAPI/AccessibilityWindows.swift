import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import os

/// The undocumented HIServices function `_AXUIElementCreateWithRemoteToken`:
/// an app's windows on every Space, where the public `kAXWindowsAttribute`
/// lists only those on the current one. Window managers (AltTab among them)
/// have relied on it for years.
///
/// A token names one Accessibility element of a process: its pid, 0, the
/// magic number 0x636f636f ("coco") and the element's number. Numbers are
/// given out as the process makes elements and never reused, so a window
/// made early has a low one, and one made again later a higher one. The
/// windows are found by trying the numbers below `elementLimit` (measured:
/// about 70 ms), and above it only when none is there (`windowNumbers`).
///
/// Resolved at runtime; if a macOS update removes it, `windows(ofProcess:)`
/// returns `nil` and only the current Space's windows can be reached.
///
/// Check after every major macOS release.
package enum AccessibilityWindows {
    /// Element numbers always tried. A Safari web app's windows stay below
    /// 100 (its page's elements belong to WebKit's process): measured, each
    /// window it opens again takes about 7 more.
    static let elementLimit: UInt64 = 1000
    /// How far numbers are tried when no window is below `elementLimit`: an
    /// Electron app numbers its page's elements in its own process (one read
    /// of Deezer's page took about 490), so a window it makes again later can
    /// be well above (Deezer's: #2353, measured 2026-10-12).
    static let farLimit: UInt64 = 100_000
    /// Above `elementLimit`, the search stops this far past the last window
    /// found: an app's windows are made close together (Spotify's: #42, #44,
    /// #46).
    static let gapAfterWindow: UInt64 = 1000
    /// How long a single element may take to answer.
    static let timeout: Float = 0.3
    /// The whole search stops after this long: an app that doesn't answer
    /// (frozen) would otherwise take `timeout` for each of the numbers.
    /// Numbers that answer nothing are quick: 20,000 in 0.6 s (measured).
    static let budget: TimeInterval = 1

    /// Whether the function is there.
    package static var isAvailable: Bool { function != nil }

    /// Per process, the first window number found above `elementLimit`: a
    /// later search starts there, as numbers only grow.
    private static let farStart = OSAllocatedUnfairLock<[pid_t: UInt64]>(initialState: [:])

    /// The process's windows on every Space, minimized ones included; `nil`
    /// when the function is unavailable. Any kind of window counts: a
    /// minimized Safari web app's window calls itself a dialog (measured).
    package static func windows(ofProcess pid: pid_t) -> [AXUIElement]? {
        guard let function else { return nil }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
        var found: [UInt64: AXUIElement] = [:]
        let numbers = windowNumbers(
            farStart: farStart.withLock { $0[pid] },
            hasWindowOutOfSight: { hasWindowOutOfSight(pid: pid) },
            deadline: Date().addingTimeInterval(budget)
        ) { number in
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: number) { Data($0) })
            guard let element = function(token as CFData)?.takeRetainedValue() else { return false }
            AXUIElementSetMessagingTimeout(element, timeout)
            guard element.string(kAXRoleAttribute) == kAXWindowRole else { return false }
            found[number] = element
            return true
        }
        if let far = numbers.first(where: { $0 >= elementLimit }) {
            farStart.withLock { $0[pid] = far }
        }
        return numbers.compactMap { found[$0] }
    }

    /// The element numbers that are windows (`isWindow`), in order: every
    /// one below `elementLimit`. Only when none is there and the process has
    /// a window out of sight (`hasWindowOutOfSight`: none would mean a
    /// second's search for nothing) are the numbers above tried, from
    /// `farStart` (where one was found before) or `elementLimit`, up to
    /// `farLimit`, ending `gapAfterWindow` past the last one found. Never past
    /// `deadline`.
    package static func windowNumbers(
        farStart: UInt64?,
        hasWindowOutOfSight: () -> Bool,
        deadline: Date,
        now: () -> Date = Date.init,
        isWindow: (UInt64) -> Bool
    ) -> [UInt64] {
        var windows: [UInt64] = []
        for number in 0..<elementLimit where now() < deadline {
            if isWindow(number) { windows.append(number) }
        }
        guard windows.isEmpty, now() < deadline, hasWindowOutOfSight() else { return windows }
        var number = max(elementLimit, farStart ?? elementLimit)
        while number < farLimit, now() < deadline {
            if let last = windows.last, number - last > gapAfterWindow { break }
            if isWindow(number) { windows.append(number) }
            number += 1
        }
        return windows
    }

    /// Whether the window server holds a window of the process that isn't on
    /// screen and is big enough to be a document window (not a strip or a
    /// helper): one on another Space, or hidden. Its owner, layer, bounds and
    /// whether it's on screen need no permission.
    static func hasWindowOutOfSight(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return true }
        return list.contains { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowIsOnscreen as String] as? Bool != true,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }
            return frame.width >= 200 && frame.height >= 200
        }
    }

    private typealias Function = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let function: Function? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken")
        else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()
}
