import Foundation

/// While AutoHush's windows are open, follows once a second what they show
/// that macOS doesn't announce (see GLOSSARY.md): the players installed,
/// the permissions, whether notifications are on, launch at login,
/// Diagnostics. Each window says once what it needs; each second the watch
/// refreshes what the open ones need, together, and it stops when none is
/// open. A window that opens wakes it.
@MainActor
final class WindowWatch {
    /// What a window shows that needs following, refreshed in this order.
    enum Refresh: Int, CaseIterable, Comparable {
        /// The players installed (the window lists them).
        case players
        /// What AutoHush sees (Settings → Diagnostics).
        case diagnostics
        /// Whether AutoHush's notifications are on, turned off or reset in
        /// System Settings.
        case notifications
        case launchAtLogin
        /// The permissions AutoHush needs: a window waiting for one goes on
        /// by itself once it's allowed.
        case permissions

        static func < (lhs: Refresh, rhs: Refresh) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Window {
        let isOpen: @MainActor () -> Bool
        let needs: @MainActor () -> Set<Refresh>
    }

    private var windows: [Window] = []
    private var loop: Task<Void, Never>?
    private let interval: Duration
    private let sleep: @Sendable (Duration) async -> Void
    private let refresh: @MainActor (Refresh) async -> Void
    private let everyTick: @MainActor () -> Void

    /// `refresh` does each refresh; `everyTick` runs after each round, and
    /// once more as the watch stops.
    init(interval: Duration = .seconds(1),
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         refresh: @escaping @MainActor (Refresh) async -> Void,
         everyTick: @escaping @MainActor () -> Void = {}) {
        self.interval = interval
        self.sleep = sleep
        self.refresh = refresh
        self.everyTick = everyTick
    }

    /// A window to follow while `isOpen`, refreshing `needs` (asked again
    /// each second: what a window shows can change while it's open).
    func register(isOpen: @escaping @MainActor () -> Bool, needs: @escaping @MainActor () -> Set<Refresh>) {
        windows.append(Window(isOpen: isOpen, needs: needs))
    }

    /// A window opened: the watch starts over at once, and runs while any
    /// window is open.
    func wake() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled, let self, let needs = self.openWindowsNeeds() {
                for need in needs.sorted() { await self.refresh(need) }
                self.everyTick()
                await self.sleep(self.interval)
            }
            self?.everyTick()
        }
    }

    /// What the open windows need, together; `nil` when none is open.
    private func openWindowsNeeds() -> Set<Refresh>? {
        let open = windows.filter { $0.isOpen() }
        guard !open.isEmpty else { return nil }
        return open.reduce(into: Set<Refresh>()) { $0.formUnion($1.needs()) }
    }
}
