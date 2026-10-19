import Foundation
import Testing
@testable import ScriptablePlayers

@Suite("ScriptedSong")
struct ScriptedSongTests {
    @Test("what an app plays is read from its current track's name, else a property of its own naming it; none without either")
    func whereItSays() throws {
        var dictionary = ScriptingDictionary()
        #expect(ScriptedSong(dictionary: dictionary) == nil)
        dictionary.properties = ["vlcN": "name of current item"]
        #expect(ScriptedSong(dictionary: dictionary) == .property("vlcN"))
        dictionary.properties["pTrk"] = "current track"
        #expect(ScriptedSong(dictionary: dictionary) == .currentTrack)
        for song in [ScriptedSong.currentTrack, .property("vlcN")] {
            #expect(try JSONDecoder().decode(ScriptedSong.self, from: JSONEncoder().encode(song)) == song)
        }
    }
}
