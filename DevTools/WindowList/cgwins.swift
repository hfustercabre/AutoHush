import CoreGraphics
import Foundation
// cgwins <pid|name>: a process's windows in the window server, front to back (read only).
let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for (i, w) in all.enumerated() {
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? -1
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard String(pid) == arg || owner == arg else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("z\(i) id \(w[kCGWindowNumber as String] ?? "?") layer \(w[kCGWindowLayer as String] ?? "?") onscreen \(w[kCGWindowIsOnscreen as String] ?? false) \(b["Width"] ?? 0)x\(b["Height"] ?? 0) at \(b["X"] ?? 0),\(b["Y"] ?? 0) name \(w[kCGWindowName as String] ?? "")")
}
