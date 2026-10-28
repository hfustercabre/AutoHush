import Foundation
import Testing

/// Only AddAppModel's own files (AddAppModel.swift and its `+Topic` parts)
/// set its state; the windows read it and set only the search and the
/// selection. Swift's `private(set)` holds only within one file, so with
/// the model split by topic this test keeps the rule instead (the user,
/// 2026-10-28).
@Suite("AddAppModel's state is set only by its own files")
struct AddAppModelGuardTests {
    private static let models = PackagePaths.root.appending(path: "Sources/AutoHushApp/Models")
    /// What the windows may set.
    private static let setByWindows: Set<String> = ["search", "selectedID"]

    /// The properties AddAppModel.swift declares on the model itself (four
    /// spaces in), computed ones too (those can't be set anyway); not the
    /// `private(set)` ones, which Swift guards already.
    private static func properties() throws -> [String] {
        let text = try String(contentsOf: models.appending(path: "AddAppModel.swift"), encoding: .utf8)
        let declaration = /^    (?:@ObservationIgnored )?(?:weak )?var (\w+)/.anchorsMatchLineEndings()
        return text.matches(of: declaration).map { String($0.1) }.filter { !Self.setByWindows.contains($0) }
    }

    /// Every Swift file in Sources/ but the model's own.
    private static func otherFiles() -> [URL] {
        let sources = PackagePaths.root.appending(path: "Sources")
        let found = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return found.filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasPrefix("AddAppModel") }
    }

    @Test("no other file sets one of its properties or binds to one")
    func onlyItsFilesSetIt() throws {
        let properties = try Self.properties()
        try #require(properties.count > 20, "AddAppModel's properties not found in \(Self.models.path)")
        let files = Self.otherFiles()
        try #require(files.count > 100, "Sources/ not found in \(PackagePaths.root.path)")
        let names = properties.joined(separator: "|")
        // `x.stage = …`, `x.permissions.audio = …`, `+=`, `.toggle()`, `.append(…)`, `.remove…(…)`, or `$x.stage`
        // (not a closure's `$0.stage`).
        let write = try Regex("\\.(\(names))(?:\\.\\w+)*\\s*(?:[-+]?=(?!=)|\\.toggle\\(|\\.append|\\.remove)")
        let binding = try Regex("\\$[A-Za-z_]\\w*\\.(\(names))\\b")
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains(write) || line.contains(binding) {
                Issue.record("\(file.lastPathComponent):\(index + 1) sets AddAppModel's state: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }
}
