import Foundation
@testable import AutoHushKit

struct StubSourceIdentifier: AudioSourceIdentifying {
    let sources: [String: AudioSource]
    let owners: [pid_t: String]
    /// Owners of processes without a bundle ID (command-line programs), by pid.
    let ownersOfPrograms: [pid_t: AudioSource]
    init(_ sources: [String: AudioSource], owners: [pid_t: String] = [:], ownersOfPrograms: [pid_t: AudioSource] = [:]) {
        self.sources = sources
        self.owners = owners
        self.ownersOfPrograms = ownersOfPrograms
    }

    func source(for process: AudioProcessInfo) -> AudioSource {
        if process.bundleID.isEmpty, let owner = ownersOfPrograms[process.pid] { return owner }
        return sources[process.bundleID] ?? AudioSource(id: process.bundleID, name: process.bundleID)
    }

    func sourceID(forPID pid: pid_t) -> String? { owners[pid] }
}
