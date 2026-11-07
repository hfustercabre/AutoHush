import AutoHushKit
import CheckedPlayers

extension PlayerControls {
    /// A player's controls as AutoHush reports them, to choose its main one
    /// from: AppleScript (its own, recommended), its playback menu, its page
    /// (not with its window hidden), the Play/Pause key and the Now Playing
    /// panel, each but the key found working; `chosen` as its main one.
    static func choosing(_ chosen: WayOrder.Kind? = nil, switches: BackupSwitches = BackupSwitches(),
                         needsCheckAgain: Bool = false, notLearned: Bool = false) -> PlayerControls {
        let all: [Control] = [
            .init(kind: .script, result: .init(kind: .script, mark: .works)),
            .init(kind: .menu, result: .init(kind: .menu, mark: .works)),
            .init(kind: .page, result: .init(kind: .page, mark: .some, failedStates: [.hidden])),
            .init(kind: .mediaKey, result: nil),
            .init(kind: .panel, result: .init(kind: .panel, mark: .works)),
        ]
        // As `WayOrder.canBeMain`: its own, or another that worked, never the key.
        return PlayerControls(all: all, chosen: chosen, choosable: { control, index in
            control.kind != .mediaKey && (index == 0 || control.found?.worked == true)
        }, switches: switches, needsCheckAgain: needsCheckAgain, notLearned: notLearned)
    }

    /// These controls with `switches`, its main one the one they choose
    /// (`BackupSwitches.mainControl`), as AutoHush reports them once set.
    func with(_ switches: BackupSwitches) -> PlayerControls {
        Self.choosing(switches.mainControl.flatMap { WayOrder.Kind(rawValue: $0.rawValue) }, switches: switches,
                      needsCheckAgain: needsCheckAgain, notLearned: notLearned)
    }
}
