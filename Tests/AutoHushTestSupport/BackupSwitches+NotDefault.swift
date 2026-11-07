import AutoHushKit

extension BackupSwitches {
    /// Both switches away from their defaults (backups off, the panel while
    /// muted on): a test that keeps, stores or puts them back with these
    /// fails when they're dropped or reset, which the defaults would pass
    /// (the panel's default turned off, 2026-11-06).
    package static let notDefault = BackupSwitches(usesBackups: false, panelWhileMuted: true)
}
