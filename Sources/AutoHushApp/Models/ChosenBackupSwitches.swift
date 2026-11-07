import AutoHushKit

/// The chosen player's main control and backup switches, with whose they are.
struct ChosenBackupSwitches: Equatable {
    let bundleID: String
    var switches: BackupSwitches
}
