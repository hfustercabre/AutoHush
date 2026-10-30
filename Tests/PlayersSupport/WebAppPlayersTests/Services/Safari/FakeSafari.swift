import Foundation
@testable import WebAppPlayers
import AutoHushTestSupport

/// Safari, in memory. Its `var`s are set by the test before the maker
/// runs (the task it starts sees them), and only read meanwhile; what both
/// change is `Locked`.
final class FakeSafari: SafariDriving, @unchecked Sendable {
    let log = Locked<[String]>([])
    var trusted = true
    /// Whether it opens an address, and has its Add to Dock (`false`: its menu item or dialog wasn't found).
    var opens = true
    var addsToDock = true
    var loads = true
    var onAdd: (@Sendable () -> Void)?
    /// As the dialog closes, with Add or Cancel.
    var onClosed: (@Sendable () -> Void)?

    func isTrusted(prompt: Bool) async -> Bool { log.append("trusted"); return trusted }
    func open(_ url: URL) async -> Bool { log.append("open \(url.absoluteString)"); return opens }
    /// The dialog stays open until the task is cancelled.
    var holdsDialog = false

    /// The page keeps loading until the task is cancelled.
    var holdsPage = false

    func waitForPage() async -> SafariTab? {
        log.append("wait")
        while holdsPage, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return loads && !Task.isCancelled ? SafariTab(page: 1) : nil
    }
    /// The front page's address at each look, the last one staying; none:
    /// it can't be read.
    let pages = Locked<[URL]>([])
    /// The tab in front once the site shows after asking something: the same
    /// one, unless the test says the page changed (`frontTabPage`).
    let frontTabPage = Locked<Int>(1)
    func frontTab() async -> SafariTab? { log.append("front tab"); return SafariTab(page: frontTabPage.value) }

    func frontPageURL() async -> URL? {
        log.append("page")
        return pages.withLock { pages in
            defer { if pages.count > 1 { pages.removeFirst() } }
            return pages.first
        }
    }
    /// Whether each time the dialog opens the user clicks Add (`true`) or
    /// Cancel there; the last one stays.
    let adds = Locked<[Bool]>([true])

    func addToDock(_ url: URL) async -> AddToDockResult {
        log.append("add \(url.absoluteString)")
        guard addsToDock else { return .unavailable }
        while holdsDialog, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        guard !Task.isCancelled else {
            log.append("cancel dialog")
            return .cancelled
        }
        let added = adds.withLock { adds in
            defer { if adds.count > 1 { adds.removeFirst() } }
            return adds.first ?? true
        }
        if added { onAdd?() }
        onClosed?()
        return .closed
    }
    func closeTab(_ tab: SafariTab) async { log.append("close tab \(tab.page)") }
}
