import Foundation
import os

/// A command-line tool run to its end, or for `timeout` at most: what it
/// printed, and how it ended. The one way AutoHush runs a tool and waits for
/// it (2026-10-19: seven hand-written ones had four timeout behaviours).
///
/// Its output is read as it comes, on a queue of its own (a full pipe would
/// stall the tool), and its end is waited for without holding one of
/// Swift's shared threads. At the timeout it's stopped, and the run ends
/// then, whether the tool does or not: one stuck in the kernel can't hold
/// its caller. One that doesn't end within `killGrace` after is killed.
package struct ToolRun: Sendable {
    let executable: URL
    let arguments: [String]
    /// How long it may take; `nil`, as long as it takes.
    var timeout: TimeInterval?
    /// Its standard error read with its output; else dropped.
    var readsErrors: Bool

    package init(_ executable: URL, _ arguments: [String] = [], timeout: TimeInterval? = nil, readsErrors: Bool = false) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.readsErrors = readsErrors
    }

    /// How it ended.
    package struct Result: Equatable, Sendable {
        /// Its exit status, or the number of the signal that ended it
        /// (`bySignal`); -1 when it couldn't start or took too long.
        package var status: Int32
        /// A signal ended it: it crashed, or was stopped.
        package var bySignal = false
        /// It took longer than its timeout, and was stopped.
        var timedOut = false
        /// What it printed; nothing for `start`, whose lines went to `onLine`.
        package var output = Data()

        init(status: Int32, bySignal: Bool = false, timedOut: Bool = false, output: Data = Data()) {
            self.status = status
            self.bySignal = bySignal
            self.timedOut = timedOut
            self.output = output
        }

        /// It couldn't start.
        package static let notStarted = Result(status: -1)

        /// It ran to its end and exited with 0.
        package var succeeded: Bool { status == 0 && !bySignal && !timedOut }
        package var text: String { String(decoding: output, as: UTF8.self) }
    }

    /// How much of its output is kept: the rest is read and dropped, so a
    /// tool that never stops printing neither fills the memory nor stalls.
    static let maxOutput = 16 << 20

    /// Runs it and waits for its end, without holding a thread meanwhile.
    package func run() async -> Result {
        await withCheckedContinuation { continuation in
            do {
                try launch(read: { Self.readAll($0) }, onEnd: { continuation.resume(returning: $0) })
            } catch {
                continuation.resume(returning: .notStarted)
            }
        }
    }

    /// Runs it, blocking the calling thread until its end: for callers that
    /// can't wait otherwise, on a thread or queue of their own (never Swift's
    /// shared threads).
    package func runBlocking() -> Result {
        let ended = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock<Result>(initialState: .notStarted)
        do {
            try launch(read: { Self.readAll($0) }, onEnd: { ending in
                result.withLock { $0 = ending }
                ended.signal()
            })
        } catch {
            return .notStarted
        }
        ended.wait()
        return result.withLock { $0 }
    }

    /// Starts it: `onLine` gets each line it prints as it comes (the last
    /// one too, without its line break), then `onEnd` how it ended, after
    /// the last line. Throws when it can't start.
    package func start(onLine: @escaping @Sendable (String) -> Void,
                       onEnd: @escaping @Sendable (Result) -> Void) throws -> Running {
        try launch(read: { handle in
            var pending = Data()
            while case let data = Self.nextBytes(handle), !data.isEmpty {
                pending.append(data)
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    onLine(String(decoding: pending[..<newline], as: UTF8.self))
                    pending.removeSubrange(...newline)
                }
            }
            if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
            return Data()
        }, onEnd: onEnd)
    }

    /// What `handle` gives until its end, up to `maxOutput`.
    private static func readAll(_ handle: FileHandle) -> Data {
        var output = Data()
        while case let data = nextBytes(handle), !data.isEmpty {
            if output.count < maxOutput { output.append(data.prefix(maxOutput - output.count)) }
        }
        return output
    }

    /// The next bytes `handle` gives, as they come; empty at its end, or on
    /// a read error. `read(2)`, not `FileHandle.availableData`, which raises
    /// an Objective-C exception on an error: a crash Swift can't catch.
    private static func nextBytes(_ handle: FileHandle) -> Data {
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let count = read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 { return Data(buffer[..<count]) }
            if count < 0, errno == EINTR { continue }
            return Data()
        }
    }

    /// How long a tool stopped at its timeout gets to end (SIGTERM) before
    /// it's killed (SIGKILL), so a stuck one doesn't stay with its reader.
    static let killGrace: TimeInterval = 5

    /// A run under way.
    package final class Running: Sendable {
        private let process: Process
        /// Whether its end was told (by the tool's end, or by the timeout).
        private let told = OSAllocatedUnfairLock(initialState: false)

        fileprivate init(process: Process) {
            self.process = process
        }

        package var isRunning: Bool { process.isRunning }

        /// Asks it to stop (SIGTERM): it may put things back before it ends.
        package func stop() {
            if process.isRunning { process.terminate() }
        }

        /// True the first time only: its end is told once.
        fileprivate func tellsEnd() -> Bool {
            told.withLock { told in
                defer { told = true }
                return !told
            }
        }
    }

    /// Starts the tool, `read` reading its output to the end on a queue of
    /// its own; `onEnd` once it has ended and its output is read, or at the
    /// timeout, whichever comes first.
    @discardableResult
    private func launch(read: @escaping @Sendable (FileHandle) -> Data,
                        onEnd: @escaping @Sendable (Result) -> Void) throws -> Running {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = readsErrors ? pipe : FileHandle.nullDevice
        let running = Running(process: process)
        // Its end and the end of its output, both waited for.
        let ended = DispatchGroup()
        ended.enter()
        process.terminationHandler = { _ in ended.leave() }
        try process.run()
        ended.enter()
        let output = OSAllocatedUnfairLock(initialState: Data())
        let handle = pipe.fileHandleForReading
        DispatchQueue(label: "AutoHush.ToolRun").async {
            let data = read(handle)
            output.withLock { $0 = data }
            ended.leave()
        }
        // Its end and its timeout are told from a queue of its own, never
        // the global one, whose few threads (one per core) callers may all
        // be holding while they wait for it: a deadlock on a 3-core Mac.
        let telling = DispatchQueue(label: "AutoHush.ToolRun.end")
        ended.notify(queue: telling) {
            guard running.tellsEnd() else { return }
            onEnd(Result(status: process.terminationStatus, bySignal: process.terminationReason == .uncaughtSignal,
                         output: output.withLock { $0 }))
        }
        if let timeout {
            telling.asyncAfter(deadline: .now() + timeout) {
                guard running.tellsEnd() else { return }
                running.stop()
                onEnd(Result(status: -1, timedOut: true))
                telling.asyncAfter(deadline: .now() + Self.killGrace) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        return running
    }
}
