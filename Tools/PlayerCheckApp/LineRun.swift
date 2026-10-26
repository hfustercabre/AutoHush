import AutoHushKit
import Foundation

/// playercheck started, as AutoHush starts it (`ToolRun.start`): its lines
/// as it prints them (its errors too), and its exit status, both awaited
/// without blocking the main thread.
struct LineRun {
    /// What Stop ends.
    let running: ToolRun.Running
    let lines: AsyncStream<String>
    private let ended: AsyncStream<Int32>

    init(_ tool: URL, _ arguments: [String]) throws {
        let (lines, line) = AsyncStream.makeStream(of: String.self)
        let (ended, end) = AsyncStream.makeStream(of: Int32.self)
        // Its end comes after its last line.
        running = try ToolRun(tool, arguments, readsErrors: true).start(onLine: { line.yield($0) }, onEnd: { result in
            line.finish()
            end.yield(result.status)
            end.finish()
        })
        self.lines = lines
        self.ended = ended
    }

    /// Its exit status, once it has ended.
    func status() async -> Int32 {
        var status: Int32 = -1
        for await code in ended { status = code }
        return status
    }
}
