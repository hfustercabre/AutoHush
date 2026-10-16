import Foundation
import Testing
@testable import AutoHushKit

@Suite("ProcessArguments")
struct ProcessArgumentsTests {
    @Test("a process's own arguments, its path first, as it was opened")
    func own() {
        let found = ProcessArguments.of(getpid())
        #expect(found == CommandLine.arguments)
    }

    @Test("none for a process that doesn't run")
    func gone() {
        #expect(ProcessArguments.of(-1).isEmpty)
        #expect(ProcessArguments.of(pid_t(Int32.max)).isEmpty)
    }
}
