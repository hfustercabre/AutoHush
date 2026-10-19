import Darwin
import Testing
@testable import AutoHushKit

@Suite("PrivateSymbol")
struct PrivateSymbolTests {
    private typealias GetPID = @convention(c) () -> pid_t

    @Test("a function found by the first of its names that's there, in what's loaded or in a library opened for it")
    func found() throws {
        let loaded = try #require(PrivateSymbol.function("getpid", as: GetPID.self))
        #expect(loaded() == getpid())
        let second = try #require(PrivateSymbol.function("AutoHushNoSuchFunction", "getpid", as: GetPID.self))
        #expect(second() == getpid())
        let opened = try #require(PrivateSymbol.function("getpid", in: "/usr/lib/libSystem.B.dylib", as: GetPID.self))
        #expect(opened() == getpid())
    }

    @Test("none when no name is there, or the library can't be opened")
    func missing() {
        #expect(PrivateSymbol.function("AutoHushNoSuchFunction", as: GetPID.self) == nil)
        #expect(PrivateSymbol.function("getpid", in: "/System/Library/PrivateFrameworks/AutoHushNoSuch.framework/AutoHushNoSuch",
                                       as: GetPID.self) == nil)
    }
}
