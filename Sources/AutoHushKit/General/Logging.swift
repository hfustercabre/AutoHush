import OSLog

extension Logger {
    /// The app's bundle identifier, used as the unified-logging subsystem.
    package static let subsystem = "com.autohush.AutoHush"

    package init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}
