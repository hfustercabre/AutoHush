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
    ) -> [ActiveAudioReport.Entry] {
        ActiveAudioReport(
            present: present, playing: playing, audible: audible, levels: levels, ignored: ignored,
            announcing: announcing, announcedBefore: announcedBefore, sources: sources
        ).entries
    }

    @Test("each app's state, sorted by ID, named when its name differs from its ID")
    func states() {
        let entries = report(
            present: ["org.videolan.vlc", "com.google.Chrome", "com.apple.Safari"],
            playing: ["com.google.Chrome"],
            audible: ["com.google.Chrome", "org.videolan.vlc"],
            ignored: ["com.apple.Safari"],
            sources: [
                "com.google.Chrome": AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
                "org.videolan.vlc": AudioSource(id: "org.videolan.vlc", name: "org.videolan.vlc"),
            ]
        )
        #expect(entries == [
            .init(id: "com.apple.Safari", state: .silent, isIgnored: true),
            .init(id: "com.google.Chrome", name: "Google Chrome", state: .playing),
            .init(id: "org.videolan.vlc", state: .starting),
        ])
    }

    @Test("an app counted as playing is listed after its output closed")
    func playingWithoutOutput() {
        #expect(report(playing: ["org.videolan.vlc"]) == [.init(id: "org.videolan.vlc", state: .playing)])
    }

    @Test("a measured level is the evidence")
    func levels() {
        let entries = report(present: ["a", "b"], levels: ["a": 0.1, "b": 0])
        #expect(entries == [
            .init(id: "a", state: .silent, evidence: .level(0.1)),
            .init(id: "b", state: .silent, evidence: .level(0)),
        ])
    }

    @Test("in AntiDot mode, what the app tells macOS replaces its level")
    func announcing() {
        let entries = report(
            present: ["a", "b"], playing: ["a"], levels: ["a": 0.5, "b": 0.5],
            announcing: ["a"], announcedBefore: ["a", "b"]
        )
        #expect(entries == [
            .init(id: "a", state: .playing, evidence: .announcing),
            .init(id: "b", state: .silent, evidence: .notAnnouncing),
        ])
    }
}
