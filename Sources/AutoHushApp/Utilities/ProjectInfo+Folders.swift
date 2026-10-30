import Foundation

// ProjectInfo: where AutoHush keeps its files on this Mac.
extension ProjectInfo {
    /// AutoHush's bundle ID, which names its folders and finds its other copies.
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.autohush.AutoHush"
    /// `~/Library/Logs/AutoHush`: its log, and its checks' beside it.
    static let logsFolder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/AutoHush", directoryHint: .isDirectory)
    /// `~/Library/Caches/<bundle ID>`.
    static let cachesFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: bundleID, directoryHint: .isDirectory)
}
