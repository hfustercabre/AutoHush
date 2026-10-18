import Foundation
import os
import AutoHushKit

/// The switches for assistive tools that AutoHush's pages use to show an
/// app's page (`AccessibilityWebPage`), shared by every page: two pages of
/// one browser (two Chrome web apps, an app checked again while its old
/// player is released) share one, which the first to go mustn't turn off
/// under the other. A switch is turned on at a page's first look on its
/// process and off as the last page using it is released, each while
/// holding `switching`: a look can't read a switch being turned off as on,
/// and leave it off. Kept by pid and the process's start, as macOS later
/// gives a quit process's pid to another, which mustn't be switched off.
final class SharedSwitches: Sendable {
    /// A switch set on a process.
    struct Key: Hashable, Sendable {
        let process: pid_t
        /// When the process started (`AccessibilityWindows.startTime(of:)`);
        /// `nil` when that couldn't be read (it quit).
        let started: UInt64?
        let attribute: String
    }

    /// The pages in AutoHush that use a switch.
    private struct Use {
        var pages: Set<UUID> = []
        /// AutoHush turned it on: the last page released turns it off.
        var turnedOn = false
    }

    private let uses = OSAllocatedUnfairLock<[Key: Use]>(initialState: [:])
    /// Held while a switch is turned on at a first look, or off at a release.
    private let switching = NSLock()
    /// When a process started: the kernel's, or a test's.
    private let startTime: @Sendable (pid_t) -> UInt64?

    init(startTime: @escaping @Sendable (pid_t) -> UInt64? = { AccessibilityWindows.startTime(of: $0) }) {
        self.startTime = startTime
    }

    /// Notes that `page` uses the switch `attribute` on `process`, turned on
    /// (`turnOn`) at the first look on that process unless it's on already
    /// (`isOn`). One that reads back as it is (`readsBack`: VoiceOver's) is
    /// read at each look, and turned on again when another tool turned it off.
    func use(_ attribute: String, on process: pid_t, by page: UUID, readsBack: Bool,
             isOn: () -> Bool, turnOn: () -> Void) {
        let key = Key(process: process, started: startTime(process), attribute: attribute)
        if !join(key, page) {
            let first = switching.withLock {
                // Another page may have come meanwhile: it's theirs to share.
                guard !join(key, page) else { return false }
                // A page that shows already has it on, by another tool maybe,
                // so it's left on at the end, as Player Check leaves it.
                let wasOn = isOn()
                if !wasOn { turnOn() }
                uses.withLock { $0[key] = Use(pages: [page], turnedOn: !wasOn) }
                return true
            }
            if first { return }
        }
        guard readsBack, !isOn() else { return }
        turnOn()
        uses.withLock { $0[key]?.turnedOn = true }
    }

    /// `page` no longer uses its switches: each that AutoHush turned on and
    /// no other page uses goes back off (`turnOff`), unless its process
    /// quit (its pid may be another's by now).
    func release(_ page: UUID, turnOff: (Key) -> Void) {
        switching.withLock {
            let unused = uses.withLock { uses in
                var unused: [Key] = []
                for (key, var use) in uses where use.pages.contains(page) {
                    use.pages.remove(page)
                    guard use.pages.isEmpty else {
                        uses[key] = use
                        continue
                    }
                    uses[key] = nil
                    if use.turnedOn { unused.append(key) }
                }
                return unused
            }
            for key in unused where key.started != nil && startTime(key.process) == key.started { turnOff(key) }
        }
    }

    /// Adds `page` to the switch's users, when it has some already.
    private func join(_ key: Key, _ page: UUID) -> Bool {
        uses.withLock { uses in
            guard uses[key] != nil else { return false }
            uses[key]?.pages.insert(page)
            return true
        }
    }
}
