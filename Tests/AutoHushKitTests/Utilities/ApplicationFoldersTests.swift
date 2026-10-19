import Foundation
import Testing
@testable import AutoHushKit

@Suite("ApplicationFolders")
struct ApplicationFoldersTests {
    @Test("apps are looked for in /Applications, the user's Applications folder and /System/Applications; web apps in the user's first")
    func folders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ApplicationFolders.all.map(\.path) == ["/Applications", "\(home)/Applications", "/System/Applications"])
        #expect(ApplicationFolders.forWebApps.map(\.path) == ["\(home)/Applications", "/Applications"])
        #expect(ApplicationFolders.all.allSatisfy { $0.hasDirectoryPath })
    }
}
