import Foundation

/// App bundles made in a test's folder, as much of one as the code under
/// test reads: its Info.plist, its frameworks and its resources.
package enum TestAppBundle {
    /// `name`.app in `folder`: its Info.plist holding `info`; each of
    /// `frameworks` in Contents/Frameworks, with `frameworkVersion` as its
    /// Resources' CFBundleVersion when given; each of `resources` (file name:
    /// text) in Contents/Resources.
    @discardableResult
    package static func make(
        in folder: URL,
        name: String,
        info: [String: Any] = [:],
        frameworks: [String] = [],
        frameworkVersion: String? = nil,
        resources: [String: String] = [:]
    ) throws -> URL {
        let app = folder.appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try (info as NSDictionary).write(to: contents.appending(path: "Info.plist"))
        for framework in frameworks {
            let frameworkResources = contents.appending(path: "Frameworks/\(framework).framework/Resources")
            try FileManager.default.createDirectory(at: frameworkResources, withIntermediateDirectories: true)
            if let frameworkVersion {
                try (["CFBundleVersion": frameworkVersion] as NSDictionary).write(to: frameworkResources.appending(path: "Info.plist"))
            }
        }
        for (file, text) in resources {
            try FileManager.default.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: contents.appending(path: "Resources/\(file)"))
        }
        return app
    }
}
