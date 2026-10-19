import Foundation

/// How to control an app by AppleScript, from what its dictionary offers
/// (`ScriptingDictionary`), as Player Check finds it: for an app added
/// through a check, without a profile of its own. Kept with the app's other
/// ways (Codable), so it's found once.
package struct ScriptSetup: Codable, Equatable, Sendable {
    /// Its commands, by code ("spfyPaus").
    package enum Commands: Codable, Equatable, Sendable {
        /// A pause and a play of their own.
        case pauseAndPlay(pause: String, play: String)
        /// One command that toggles (playpause, VLC's play): sent only from
        /// the opposite state.
        case toggle(String)
    }

    /// Where its state is read.
    package enum State: Codable, Equatable, Sendable {
        /// `player state` (pPlS): stopped, playing or paused.
        case playerState
        /// A true/false `playing` property, by code; with a `current time`
        /// (-1 with nothing loaded) to tell stopped from paused, as VLC's.
        case playingFlag(property: String, currentTime: String?)
        /// Its documents' `playing` (QuickTime Player's): it plays while one
        /// does, and is stopped with none open.
        case documents(documentClass: String, playing: String)

        /// Where `dictionary`'s state is read: its `player state` only with
        /// its three standard values, else its `playing` flag (with its
        /// `current time`), else its documents'; `nil` when it can't be read
        /// by script. Player Check reads an app's state by this too, so it
        /// judges a way by the state AutoHush reads.
        package init?(dictionary: ScriptingDictionary) {
            if dictionary.hasPlayerState, dictionary.hasStateValues {
                self = .playerState
            } else if let playing = dictionary.properties.first(where: { $0.value == "playing" })?.key {
                self = .playingFlag(property: playing, currentTime: dictionary.properties.first { $0.value == "current time" }?.key)
            } else if dictionary.playsDocuments, let documentClass = dictionary.documentClass, let playing = dictionary.documentPlaying {
                self = .documents(documentClass: documentClass, playing: playing)
            } else {
                return nil
            }
        }
    }

    package var commands: Commands
    /// Its commands act on a document (QuickTime Player's): a pause goes to
    /// each one playing, a play to those it paused, never another.
    package var actsOnDocuments: Bool
    /// `nil` when it can't be read by script: other signs tell it.
    package var state: State?
    /// Its `sound volume` (pVol, 0–100), so it can fade.
    package var hasVolume: Bool
    /// Each document's own volume, by code, 0–1 (QuickTime Player's `audio
    /// volume`), so it can fade: read from and set on its documents playing,
    /// else those it fades or paused, never another. `nil` without one.
    var documentVolume: String?

    package init(commands: Commands, actsOnDocuments: Bool = false, state: State?, hasVolume: Bool, documentVolume: String? = nil) {
        self.commands = commands
        self.actsOnDocuments = actsOnDocuments
        self.state = state
        self.hasVolume = hasVolume
        self.documentVolume = documentVolume
    }

    /// What `dictionary` offers: pause and play in its own suite, else
    /// commands named so, else one that toggles (playpause, else play); `nil`
    /// with none of them.
    package init?(dictionary: ScriptingDictionary) {
        let names = Dictionary(dictionary.commands.map { ($0.value.lowercased(), $0.key) }, uniquingKeysWith: { first, _ in first })
        if let suite = dictionary.suite {
            commands = .pauseAndPlay(pause: suite + "Paus", play: suite + "Play")
        } else if let pause = dictionary.commandCode("pause"), let play = dictionary.commandCode("play") {
            commands = .pauseAndPlay(pause: pause, play: play)
        } else if let toggle = dictionary.commandCode("playpause") ?? names["play"] {
            commands = .toggle(toggle)
        } else {
            return nil
        }
        let codes: [String] = switch commands {
        case .pauseAndPlay(let pause, let play): [pause, play]
        case .toggle(let toggle): [toggle]
        }
        actsOnDocuments = codes.allSatisfy(dictionary.documentCommands.contains)
        state = State(dictionary: dictionary)
        hasVolume = dictionary.hasVolume
    }
}
