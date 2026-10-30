import Foundation
import AutoHushKit
@testable import AutoHushApp
import AutoHushTestSupport

/// What the stand-ins (`FakeAppActions`, `FakeUpdateCommands`) were asked,
/// in order, across them.
@MainActor
final class CallLog {
    var calls: [String] = []
}
