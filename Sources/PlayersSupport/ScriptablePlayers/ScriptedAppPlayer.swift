import AppKit
import Foundation
import AutoHushKit

/// An app controlled by AppleScript as its dictionary allows it
/// (`ScriptSetup`), found by a check rather than described by a profile:
/// its own pause and play, else a command that toggles (sent only from the
/// opposite state), to its documents when they act on one (QuickTime
/// Player's). Its state is its `player state`, its `playing` flag or its
/// documents'; its notification follows it when the check saw one,
/// otherwise it's read about once a second. One whose state can't be read
/// by script toggles by `toggleState`, the app's other signs, and checks
/// that toggle itself, by them.
package actor ScriptedAppPlayer: MusicPlayer {
    package nonisolated let bundleID: String
    package nonisolated let name: String
    package nonisolated let setup: ScriptSetup
    /// Its icon while it isn't installed: a built-in player's (QuickTime
    /// Player's); none for an added app.
    package nonisolated let iconPlaceholder: PlayerIconPlaceholder?
    /// The notification that announced its pauses and plays in the check;
    /// `nil` when none did.
    package nonisolated let stateNotification: Notification.Name?

    private let channel: any AppleEventSending
    /// For a toggle without a scripted state: whether it plays, as the
    /// app's other signs tell it (`.unknown`: nothing is sent).
    private let toggleState: @Sendable () async -> PlayerState
    /// The documents it fades or paused, by name: those a volume last went to
    /// while they played, or its last pause paused. While none plays, a
    /// volume goes to them, and a play plays them again, also after one that
    /// failed; never another document (the front one, say), which may be one
    /// the user paused.
    private var documentsInHand: [String] = []
    /// The last read's failure, logged once until a read works or fails otherwise.
    private var lastFailure: String?
    private let sleep: VolumeFader.Sleep
    private let logger = AutoHushLogger(category: "ScriptedAppPlayer")

    /// `channel`: its Apple events, and `sleep`, while a toggle is checked;
    /// tests stand in for them.
    package init(bundleID: String, name: String, setup: ScriptSetup, iconPlaceholder: PlayerIconPlaceholder? = nil,
                 stateNotification: Notification.Name? = nil,
                 toggleState: @escaping @Sendable () async -> PlayerState = { .unknown }, channel: (any AppleEventSending)? = nil,
                 sleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) }) {
        self.bundleID = bundleID
        self.name = name
        self.setup = setup
        self.iconPlaceholder = iconPlaceholder
        self.stateNotification = stateNotification
        self.toggleState = toggleState
        self.channel = channel ?? AppleEventChannel(bundleID: bundleID, label: name)
        self.sleep = sleep
    }

    package nonisolated var canFade: Bool { setup.hasVolume || setup.documentVolume != nil }

    /// A toggle with no scripted state checks itself (`togglesBySigns`);
    /// any other press is checked as any player's is (`PressCheck`).
    package nonisolated var checksItsPresses: Bool { togglesBySigns }

    /// It only toggles, and whether it plays is the app's other signs':
    /// checked by them, a toggle is never sent twice, since a second would
    /// undo a first the app is only slow to show (still buffering).
    private nonisolated var togglesBySigns: Bool {
        if case .toggle = setup.commands { setup.state == nil } else { false }
    }

    package func verifyControlAccess() async throws {
        let pid = try channel.runningProcessIdentifier()
        try await channel.requestPermission(pid: pid)
    }

    package func playerState() async -> PlayerState {
        guard let pid = channel.processIdentifier() else { return .notRunning }
        do {
            let state = try await readState(of: pid)
            lastFailure = nil
            return state
        } catch {
            // Polled once a second: a read that keeps failing (Automation
            // denied, the app busy) is logged once, not every second.
            let failure = String(describing: error)
            if failure != lastFailure { logger.error("\(self.name, privacy: .public) playerState failed: \(error)") }
            lastFailure = failure
            return .unknown
        }
    }

    private func readState(of pid: pid_t) async throws -> PlayerState {
        switch setup.state {
        case nil:
            return .unknown
        case .playerState:
            return ScriptablePlayer.playerState(fromReply: try await channel.send(ScriptablePlayer.makeGetPlayerStateEvent(processIdentifier:), to: pid))
        case .playingFlag(let property, let currentTime):
            let playing = try await get(property, of: pid)
            if playing.directObjectBoolean == true { return .playing }
            // Not playing: -1 for its current time means nothing is loaded.
            guard let currentTime, let time = try await get(currentTime, of: pid).directObjectInteger else { return .paused }
            return time < 0 ? .stopped : .paused
        case .documents:
            let documents = try await documents(of: pid)
            return documents.isEmpty ? .stopped : documents.contains(where: \.playing) ? .playing : .paused
        }
    }

    package func pause() async throws {
        switch setup.commands {
        case .pauseAndPlay(let pause, _):
            try await send(pause, pausing: true)
        case .toggle(let toggle):
            guard try await stateForToggle().needsToggle(from: .playing) else { return }
            try await sendToggle(toggle, to: .paused)
        }
    }

    package func play() async throws {
        switch setup.commands {
        case .pauseAndPlay(_, let play):
            try await send(play, pausing: false)
        case .toggle(let toggle):
            guard try await stateForToggle().needsToggle(from: .paused) else { return }
            try await sendToggle(toggle, to: .playing)
        }
    }

    /// Its state before a toggle: by script, else by its other signs.
    private func stateForToggle() async -> PlayerState {
        setup.state == nil ? await toggleState() : await playerState()
    }

    /// Sends `toggle`; one judged by the app's other signs waits for them
    /// to show `target` (`PressCheck.toggleWait`), and isn't sent again.
    private func sendToggle(_ toggle: String, to target: PlayerState) async throws {
        let pausing = target == .paused
        guard togglesBySigns else { return try await send(toggle, pausing: pausing) }
        try await PressCheck(name: name, isToggle: true, press: { [self] _ in try await send(toggle, pausing: pausing) },
                             state: toggleState, sleep: sleep).press(to: target)
    }

    package func volume() async -> Int? {
        if let property = setup.documentVolume { return await documentVolume(property) }
        guard setup.hasVolume, let pid = channel.processIdentifier(),
              let reply = try? await channel.send(ScriptablePlayer.makeGetVolumeEvent(processIdentifier:), to: pid)
        else { return nil }
        return ScriptablePlayer.volume(fromReply: reply, reading: { $0 })
    }

    package func setVolume(_ volume: Int) async throws {
        let volume = min(max(volume, 0), 100)
        if let property = setup.documentVolume { return try await setDocumentVolume(property, to: volume) }
        guard setup.hasVolume else { return }
        let pid = try channel.runningProcessIdentifier()
        _ = try await channel.send({ ScriptablePlayer.makeSetVolumeEvent(volume, processIdentifier: $0) }, to: pid)
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        if let stateNotification {
            return PlayerStateObserver(notification: stateNotification, bundleID: bundleID, onChange: onChange)
        }
        return PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange)
    }

    package nonisolated var stateReportDelay: TimeInterval { stateNotification == nil ? PolledStateObserver.reportDelay : 0 }

    // MARK: - Apple events

    /// Sends the command `code` ("spfyPaus"); to documents when its commands
    /// act on one: a pause to each one playing (then in hand), a play to
    /// those in hand still open (`documentsInHand`), never another.
    private func send(_ code: String, pausing: Bool) async throws {
        let pid = try channel.runningProcessIdentifier()
        guard setup.actsOnDocuments, case .documents(let documentClass, _) = setup.state else {
            _ = try await channel.send({ ScriptedAppPlayer.makeCommandEvent(code, processIdentifier: $0) }, to: pid)
            return
        }
        let documents = try await documents(of: pid)
        let targets = pausing ? documents.filter(\.playing).map(\.name) : inHand(among: documents)
        guard !targets.isEmpty else { throw MusicPlayerError.playerCommandFailed(.nothingToPlay) }
        if pausing { documentsInHand = targets }
        for target in targets {
            _ = try await channel.send({
                ScriptedAppPlayer.makeCommandEvent(code, to: ScriptedAppPlayer.documentSpecifier(documentClass, named: target), processIdentifier: $0)
            }, to: pid)
        }
    }

    /// The documents a volume goes to: those playing, which it fades then
    /// (in hand), else those in hand still open (the one faded stopped
    /// during the fade, or its pause paused them: their volume set back,
    /// then faded in); none otherwise.
    private func volumeTargets(of pid: pid_t) async throws -> [String] {
        let documents = try await documents(of: pid)
        let playing = documents.filter(\.playing).map(\.name)
        if !playing.isEmpty { documentsInHand = playing }
        return inHand(among: documents)
    }

    /// The documents in hand that are among `documents`, those open now.
    /// With none in hand (a pause handed over by the copy before an update's
    /// relaunch), the only document open, when just one is.
    private func inHand(among documents: [(name: String, playing: Bool)]) -> [String] {
        if documentsInHand.isEmpty, documents.count == 1 { return [documents[0].name] }
        return documentsInHand.filter { name in documents.contains { $0.name == name } }
    }

    /// Its documents' `property` (0–1) as AutoHush's 0–100: the first one's
    /// a volume goes to.
    private func documentVolume(_ property: String) async -> Int? {
        guard case .documents(let documentClass, _) = setup.state, let pid = channel.processIdentifier(),
              let target = try? await volumeTargets(of: pid).first,
              let reply = try? await channel.send({
                  ScriptedAppPlayer.makeGetDataEvent(
                      ScriptedAppPlayer.propertySpecifier(property, of: ScriptedAppPlayer.documentSpecifier(documentClass, named: target)),
                      processIdentifier: $0)
              }, to: pid),
              let value = reply.directObjectReal
        else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    private func setDocumentVolume(_ property: String, to volume: Int) async throws {
        guard case .documents(let documentClass, _) = setup.state else { return }
        let pid = try channel.runningProcessIdentifier()
        for target in try await volumeTargets(of: pid) {
            _ = try await channel.send({
                ScriptedAppPlayer.makeSetDataEvent(
                    ScriptedAppPlayer.propertySpecifier(property, of: ScriptedAppPlayer.documentSpecifier(documentClass, named: target)),
                    to: NSAppleEventDescriptor(double: Double(volume) / 100), processIdentifier: $0)
            }, to: pid)
        }
    }

    private func get(_ property: String, of pid: pid_t) async throws -> PlayerReply {
        try await channel.send({ ScriptablePlayer.makeGetPropertyEvent(ScriptedAppPlayer.code(property), processIdentifier: $0) }, to: pid)
    }

    /// Its open documents, front first: each one's name and whether it plays.
    private func documents(of pid: pid_t) async throws -> [(name: String, playing: Bool)] {
        guard case .documents(let documentClass, let playing) = setup.state else { return [] }
        let names = try await channel.send({
            ScriptedAppPlayer.makeGetDataEvent(ScriptedAppPlayer.propertySpecifier("pnam", of: ScriptedAppPlayer.documentSpecifier(documentClass)),
                                               processIdentifier: $0)
        }, to: pid)
        let flags = try await channel.send({
            ScriptedAppPlayer.makeGetDataEvent(ScriptedAppPlayer.propertySpecifier(playing, of: ScriptedAppPlayer.documentSpecifier(documentClass)),
                                               processIdentifier: $0)
        }, to: pid)
        // One document answers with its value, not a list of one.
        let nameList = names.listTexts.isEmpty ? names.directObjectText.map { [$0] } ?? [] : names.listTexts
        let flagList = flags.listBooleans.isEmpty ? flags.directObjectBoolean.map { [$0] } ?? [] : flags.listBooleans
        return Array(zip(nameList, flagList).map { (name: $0, playing: $1) })
    }
}
