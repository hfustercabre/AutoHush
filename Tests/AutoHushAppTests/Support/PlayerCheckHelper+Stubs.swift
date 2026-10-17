import Foundation
@testable import AutoHushApp

extension PlayerCheckHelper {
    /// A stand-in for playercheck in `folder`: a shell script that runs
    /// `body`. Its logs and caches go in `folder` too (Logs, Caches), never
    /// in AutoHush's.
    static func standIn(_ body: String, in folder: URL) throws -> PlayerCheckHelper {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "playercheck")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        var helper = PlayerCheckHelper(url: url)
        helper.logs = folder.appending(path: "Logs")
        helper.caches = folder.appending(path: "Caches")
        return helper
    }
}
