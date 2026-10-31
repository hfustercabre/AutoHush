import AppKit
import AutoHushKit
import ScriptablePlayers

// MARK: - Its state and its song, by script

/// macOS refused the app's state (-1743), or --partial went on without
/// Automation: it's no longer asked. Each kind of error, and each unknown
/// state value, is said once.
@MainActor var scriptRefused = false
/// Its state by script said it didn't play while it was heard (an app whose
/// `player state` reads stopped while it plays a stream, 2026-10-22): wrong
/// for this app, so it's no longer read, and AutoHush isn't given it
/// (`writeResult`): other signs tell its state.
@MainActor var scriptStateWrong = false
@MainActor var scriptErrorsSaid: Set<Int> = []
@MainActor var unknownStatesSaid: Set<FourCharCode> = []

/// The app's state by script, read where AutoHush reads it (`scriptState`)
/// and when it answers: its `player state`, only with its three standard
/// values (stopped, playing, paused, read as AutoHush reads it:
/// `ScriptablePlayer.playerState(fromEnumCode:)`, which counts fast
/// forwarding and rewinding as playing), else its `playing` flag (with its
/// `current time` telling stopped from paused), else its documents'
/// (playing while one is, stopped with none open), asked by Apple event.
/// Only macOS refusing it (-1743: no Automation permission for whatever
/// runs this tool), or its state found wrong (`scriptStateWrong`), stops the
/// asking; another error (a timeout, -1712, from a busy app) counts for that
/// look only.
@MainActor func scriptedState() -> PlayerState? {
    guard let scriptState, !scriptRefused, !scriptStateWrong else { return nil }
    func failed(_ error: NSError) -> PlayerState? {
        noteScriptError(error.code)
        let refused = error.code == -1743
        if refused { scriptRefused = true }
        if scriptErrorsSaid.insert(error.code).inserted {
            say("  its state can't be read by script: \(eventError(error))" + (refused ? "" : " (asked again at the next look)"))
        }
        return nil
    }
    switch scriptState {
    case .documents(let documentClass, let playing):
        switch scriptedDocuments(documentClass, playing: playing) {
        case .failure(let error): return failed(error)
        case .success(let documents): return ScriptSetup.State.state(documentsPlaying: documents.map(\.playing))
        }
    case .playingFlag(let playing, let currentTime):
        switch getProperty(playing) {
        case .failure(let error):
            return failed(error)
        case .success(let result):
            guard let result else { return nil }
            // Not playing: its `current time` tells stopped from paused, as
            // AutoHush reads it (an unread one: paused).
            var time: Int?
            if !result.booleanValue, let currentTime, case .success(let reply?) = getProperty(currentTime) { time = Int(reply.int32Value) }
            return ScriptSetup.State.state(playing: result.booleanValue, currentTime: time)
        }
    case .playerState:
        switch getProperty("pPlS") {
        case .failure(let error):
            return failed(error)
        case .success(let result):
            guard let result else { return nil }
            let code = result.enumCodeValue
            let state = ScriptablePlayer.playerState(fromEnumCode: code)
            if state == .unknown, unknownStatesSaid.insert(code).inserted {
                say("  its state reads “\(fourCharacters(code))”, a value AutoHush doesn't know: taken as not playing")
            }
            return state
        }
    }
}

/// The name of what it plays, by Apple event, when its dictionary has a
/// `current track`, else a `name of current item`. It stays while paused,
/// where a window's title may not (a paused app's may say just its name),
/// and it's read wherever its window is (one on another desktop may be out
/// of Accessibility's reach).
/// Nil without one, or when it doesn't answer (nothing loaded).
@MainActor func scriptedSong() -> String? {
    guard let scripting, scripting.namesItsSong, !scriptRefused else { return nil }
    let specifier = scripting.hasCurrentTrack || scripting.currentItemName == nil
        ? ScriptedAppPlayer.propertySpecifier("pnam", of: propertySpecifier("pTrk")) : propertySpecifier(scripting.currentItemName!)
    switch getData(of: specifier) {
    case .failure(let error):
        noteScriptError(error.code)
        return nil
    case .success(let result):
        return result?.stringValue
    }
}
