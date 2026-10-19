import Foundation

/// Waiting on the calling thread until something holds, looking at it every
/// so often: for what macOS doesn't announce (a window coming forward, a
/// panel's rows showing). Between looks the thread sleeps, or runs its run
/// loop with `runLoop` (for the notifications and timers due meanwhile).
package enum Polling {
    /// Looks at `done` every `interval` until it holds (true) or `seconds`
    /// have passed (false, its last look made then). With `lookingFirst`
    /// off it waits an interval before its first look (what it waits for
    /// can't hold yet). With `lookingLate` off, the time is checked after
    /// each pause instead of before it: no look is made once it's up.
    @discardableResult
    package static func wait(seconds: Double, every interval: Double, runLoop: Bool = false, lookingFirst: Bool = true,
                             lookingLate: Bool = true, until done: () -> Bool) -> Bool {
        wait(seconds: seconds, every: interval, runLoop: runLoop, lookingFirst: lookingFirst, lookingLate: lookingLate,
             reading: done, until: { $0 })
    }

    /// `wait(seconds:every:runLoop:lookingFirst:lookingLate:until:)` keeping
    /// what it looks at: reads `read` until `done` holds of it, and returns
    /// the last read.
    package static func wait<Value>(seconds: Double, every interval: Double, runLoop: Bool = false, lookingFirst: Bool = true,
                                    lookingLate: Bool = true, reading read: () -> Value, until done: (Value) -> Bool) -> Value {
        let deadline = Date().addingTimeInterval(seconds)
        if !lookingFirst { pause(interval, runLoop: runLoop) }
        return poll(until: deadline, every: interval, runLoop: runLoop, lookingLate: lookingLate, from: read(), reading: read, until: done)
    }

    /// The same wait from a first look already made (`first`, read before
    /// something was said or done): it ends at once if `done` holds of it,
    /// else waits an interval before reading again.
    package static func wait<Value>(seconds: Double, every interval: Double, runLoop: Bool = false, from first: Value,
                                    reading read: () -> Value, until done: (Value) -> Bool) -> Value {
        poll(until: Date().addingTimeInterval(seconds), every: interval, runLoop: runLoop, lookingLate: true, from: first,
             reading: read, until: done)
    }

    private static func poll<Value>(until deadline: Date, every interval: Double, runLoop: Bool, lookingLate: Bool, from first: Value,
                                    reading read: () -> Value, until done: (Value) -> Bool) -> Value {
        var value = first
        while !done(value), !lookingLate || Date() < deadline {
            pause(interval, runLoop: runLoop)
            if !lookingLate, Date() >= deadline { break }
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
