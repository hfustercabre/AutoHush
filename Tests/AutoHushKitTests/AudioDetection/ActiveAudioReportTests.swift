import Testing
@testable import AutoHushKit

@Suite("ActiveAudioReport")
struct ActiveAudioReportTests {
    private func report(
        present: Set<String> = [],
        playing: Set<String> = [],
        audible: Set<String> = [],
        levels: [String: Float] = [:],
        ignored: Set<String> = [],
        announcing: Set<String> = [],
        announcedBefore: Set<String> = [],
        sources: [String: AudioSource] = [:]
    ) -> [String] {
        ActiveAudioReport(
            present: present, playing: playing, audible: audible, levels: levels, ignored: ignored,
            announcing: announcing, announcedBefore: announcedBefore, sources: sources
        ).lines
    }

    @Test("each app's state, sorted by ID, named when its name differs from its ID")
    func states() {
        let lines = report(
            present: ["org.videolan.vlc", "com.google.Chrome", "com.apple.Safari"],
            playing: ["com.google.Chrome"],
            audible: ["com.google.Chrome", "org.videolan.vlc"],
            ignored: ["com.apple.Safari"],
            sources: ["com.google.Chrome": AudioSource(id: "com.google.Chrome", name: "Google Chrome")]
        )
        #expect(lines == [
            "com.apple.Safari — output open, silent, ignored",
            "Google Chrome (com.google.Chrome) — playing",
            "org.videolan.vlc — starting",
        ])
    }

    @Test("an app counted as playing is listed after its output closed")
    func playingWithoutOutput() {
        #expect(report(playing: ["org.videolan.vlc"]) == ["org.videolan.vlc — playing"])
    }

    @Test("levels are shown in dBFS, and zero as silence")
    func levels() {
        let lines = report(present: ["a", "b"], levels: ["a": 0.1, "b": 0])
        #expect(lines == ["a — output open, silent (-20 dBFS)", "b — output open, silent (silence)"])
    }

    @Test("in AntiDot mode, what the app tells macOS replaces its level")
    func announcing() {
        let lines = report(
            present: ["a", "b"], playing: ["a"], levels: ["a": 0.5, "b": 0.5],
            announcing: ["a"], announcedBefore: ["a", "b"]
        )
        #expect(lines == [
            "a — playing (tells macOS it is playing)",
            "b — output open, silent (not telling macOS it is playing)",
        ])
    }
}
