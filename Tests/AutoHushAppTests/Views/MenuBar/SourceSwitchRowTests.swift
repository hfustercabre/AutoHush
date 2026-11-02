import Testing
@testable import AutoHushApp
import AutoHushKit

/// What an app's row in the menu says under its name, to VoiceOver and in
/// its help tag.
@Suite("SourceSwitchRow")
@MainActor
struct SourceSwitchRowTests {
    private let safari = AudioSource(id: "com.apple.Safari", name: "Safari")

    private var soundOn: AudioSource {
        var source = safari
        source.isOpenOutputOnly = true
        return source
    }

    @Test("in Playing Now, an app that counts only because its sound is open says it may be paused, with what to do in its help tag and VoiceOver hint")
    func soundOnInPlayingNow() {
        let words = SourceSwitchRow.words(for: soundOn, isIgnored: false, mutes: false, playsNow: true, saysIgnoredShortly: false)
        #expect(words.subtitle == "Sound on, may be paused")
        #expect(words.help == "Close it, or ignore it, if it isn’t playing.")
        #expect(words.hint == "Sound on, may be paused. Close it, or ignore it, if it isn’t playing.")
        // Muted rather than paused, it still may be paused itself.
        #expect(SourceSwitchRow.words(for: soundOn, isIgnored: false, mutes: true, playsNow: true, saysIgnoredShortly: false) == words)
    }

    @Test("an app that tells macOS it plays, or is measured, says what it does to the player, without a help tag")
    func pausesYourPlayer() {
        let words = SourceSwitchRow.words(for: safari, isIgnored: false, mutes: false, playsNow: true, saysIgnoredShortly: false)
        #expect(words == .init(subtitle: "Pauses your player", hint: "Pauses your player", help: nil))
        #expect(SourceSwitchRow.words(for: safari, isIgnored: false, mutes: true, playsNow: true, saysIgnoredShortly: false).subtitle
            == "Mutes your player")
    }

    @Test("ignored, or no longer playing (Recently Played), an app that counted only by its open sound says what it says today")
    func soundOnOnlyWhilePlayingAndCounted() {
        #expect(SourceSwitchRow.words(for: soundOn, isIgnored: true, mutes: false, playsNow: true, saysIgnoredShortly: false)
            == .init(subtitle: IgnoredText.label, hint: IgnoredText.label, help: nil))
        #expect(SourceSwitchRow.words(for: soundOn, isIgnored: true, mutes: false, playsNow: false, saysIgnoredShortly: true)
            == .init(subtitle: "Ignored", hint: "Ignored", help: nil))
        #expect(SourceSwitchRow.words(for: soundOn, isIgnored: false, mutes: false, playsNow: false, saysIgnoredShortly: false)
            == .init(subtitle: "Pauses your player", hint: "Pauses your player", help: nil))
    }
}
