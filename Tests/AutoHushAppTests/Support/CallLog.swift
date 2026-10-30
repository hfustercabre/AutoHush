import Foundation

/// What the stand-ins (`FakeAppActions`, `FakeUpdateCommands`) were asked,
/// in order, across them.
@MainActor
final class CallLog {
    var calls: [String] = []
}
