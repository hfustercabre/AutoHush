import Foundation

/// Waiting on the calling thread until something holds, looking at it every
/// so often: for what macOS doesn't announce (a window coming forward, a
/// panel's rows showing). Between looks the thread sleeps, or runs its run
/// loop with `runLoop` (for the notifications and timers due meanwhile).
package enum Polling {
    /// Looks at `done` every `interval` until it holds (true) or `seconds`
    /// have passed (false, its last look made then). With `lookingFirst`
    /// off it waits an interval before its first look (what it waits for
    /// can't hold yet).
    @discardableResult
    package static func wait(seconds: Double, every interval: Double, runLoop: Bool = false, lookingFirst: Bool = true,
                             until done: () -> Bool) -> Bool {
        wait(seconds: seconds, every: interval, runLoop: runLoop, lookingFirst: lookingFirst, reading: done, until: { $0 })
    }

    /// `wait(seconds:every:runLoop:lookingFirst:until:)` keeping what it
    /// looks at: reads `read` until `done` holds of it, and returns the last
    /// read.
    package static func wait<Value>(seconds: Double, every interval: Double, runLoop: Bool = false, lookingFirst: Bool = true,
                                    reading read: () -> Value, until done: (Value) -> Bool) -> Value {
        let deadline = Date().addingTimeInterval(seconds)
        if !lookingFirst { pause(interval, runLoop: runLoop) }
        var value = read()
        while !done(value), Date() < deadline {
            pause(interval, runLoop: runLoop)
            value = read()
        }
        return value
    }

    private static func pause(_ interval: Double, runLoop: Bool) {
        if runLoop {
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        } else {
            Thread.sleep(forTimeInterval: interval)
        }
    }
}
