import AppKit

/// A function of macOS's private frameworks by one of its names, as window
/// managers resolve them at run time; nil when gone.
func privateSymbol<T>(_ names: String..., as type: T.Type) -> T? {
    for name in names {
        if let found = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return unsafeBitCast(found, to: type) }
    }
    return nil
}

/// macOS's desktops (Spaces), read through SkyLight's read-only calls, as
/// window managers read them. Only the main display's.
enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let connection = privateSymbol("SLSMainConnectionID", "CGSMainConnectionID", as: MainConnection.self)
    private static let displaySpaces = privateSymbol("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces", as: CopyDisplaySpaces.self)
    private static let spacesForWindows = privateSymbol("SLSCopySpacesForWindows", "CGSCopySpacesForWindows", as: CopySpacesForWindows.self)

    /// The main display's desktops in order (full screen apps' among them),
    /// and the current one.
    static func all() -> (spaces: [(id: Int, isFullScreen: Bool)], current: Int)? {
        guard let connection, let displaySpaces,
              let main = (displaySpaces(connection())?.takeRetainedValue() as? [[String: Any]])?.first else { return nil }
        func id(_ space: [String: Any]?) -> Int { (space?["ManagedSpaceID"] as? Int) ?? (space?["id64"] as? Int) ?? 0 }
        let listed = main["Spaces"] as? [[String: Any]] ?? []
        let spaces: [(id: Int, isFullScreen: Bool)] = listed.map { space in (id: id(space), isFullScreen: space["type"] as? Int == 4) }
        guard !spaces.isEmpty else { return nil }
        return (spaces, id(main["Current Space"] as? [String: Any]))
    }

    /// The desktop a window is on.
    static func of(window: Int) -> Int? {
        guard let connection, let spacesForWindows,
              let spaces = spacesForWindows(connection(), 7, [window] as CFArray)?.takeRetainedValue() as? [Int] else { return nil }
        return spaces.first
    }

    /// Where a desktop is in the main display's order.
    static func index(of id: Int) -> Int? { all()?.spaces.firstIndex { $0.id == id } }
}
