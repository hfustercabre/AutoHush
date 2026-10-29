import AppKit

/// macOS's desktops (Spaces), read through SkyLight's read-only calls, as
/// window managers read them. Only the main display's. Player Check moves
/// windows between them; Add an App reads where an app's windows are
/// (`AppWindows`).
package enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let connection = PrivateSymbol.function("SLSMainConnectionID", "CGSMainConnectionID", as: MainConnection.self)
    private static let displaySpaces = PrivateSymbol.function("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces",
                                                               as: CopyDisplaySpaces.self)
    private static let spacesForWindows = PrivateSymbol.function("SLSCopySpacesForWindows", "CGSCopySpacesForWindows",
                                                                  as: CopySpacesForWindows.self)

    /// The main display's desktops in order (full screen apps' among them),
    /// and the current one.
    package static func all() -> (spaces: [(id: Int, isFullScreen: Bool)], current: Int)? {
        guard let connection, let displaySpaces,
              let main = (displaySpaces(connection())?.takeRetainedValue() as? [[String: Any]])?.first else { return nil }
        func id(_ space: [String: Any]?) -> Int { (space?["ManagedSpaceID"] as? Int) ?? (space?["id64"] as? Int) ?? 0 }
        let listed = main["Spaces"] as? [[String: Any]] ?? []
        let spaces: [(id: Int, isFullScreen: Bool)] = listed.map { space in (id: id(space), isFullScreen: space["type"] as? Int == 4) }
        guard !spaces.isEmpty else { return nil }
        return (spaces, id(main["Current Space"] as? [String: Any]))
    }

    /// The desktop a window is on.
    package static func of(window: Int) -> Int? { all(ofWindow: window)?.first }

    /// The desktops a window is on: none for a window closed or ordered out
    /// (a minimized or hidden one keeps its own); nil when they can't be read.
    package static func all(ofWindow window: Int) -> [Int]? {
        guard let connection, let spacesForWindows else { return nil }
        return spacesForWindows(connection(), 7, [window] as CFArray)?.takeRetainedValue() as? [Int]
    }

    /// Where a desktop is in the main display's order.
    package static func index(of id: Int) -> Int? { all()?.spaces.firstIndex { $0.id == id } }
}
