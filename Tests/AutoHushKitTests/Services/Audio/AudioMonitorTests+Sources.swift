import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
    // MARK: - The player playing on this Mac vs. another device

    @Test("the player without running output is reported as not playing on this Mac")
    func playerWithoutOutputIsNotLocal() async {
        let h = Harness()
        h.start()
        h.step([])
        await h.recorder.waitForPlayerLocal(count: 1)
        #expect(await h.recorder.playerLocal == [false])
    }

    @Test("the player's output counts as local when levels are unavailable")
    func playerOutputIsLocalWithoutLevels() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        await h.recorder.waitForPlayerLocal(count: 2)
        // The start-up evaluation runs before any process exists.
        #expect(await h.recorder.playerLocal == [false, true])
    }

    @Test("the player counts as playing here exactly while its output runs")
    func playerLocalFollowsOutput() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        await h.recorder.waitForPlayerLocal(count: 2)
        h.step(after: 0.25, [])
        await h.recorder.waitForPlayerLocal(count: 3)
        #expect(await h.recorder.playerLocal == [false, true, false])
        #expect(h.meter.lastMetered.isEmpty)
    }

    @Test("a process the player owns is its output, never a source: a web app's WebKit process, or a command-line program it runs",
          arguments: ["com.apple.WebKit.GPU", ""])
    func playerOwnedProcessIsLocal(bundleID: String) async {
        let jukebox = AudioSource(id: TestPlayer.bundleID, name: "Jukebox")
        let identifier = StubSourceIdentifier(["com.apple.WebKit.GPU": jukebox], ownersOfPrograms: [1001: jukebox])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, bundleID)]) // pid 1001
        await h.recorder.waitForPlayerLocal(count: 2)
        #expect(await h.recorder.playerLocal == [false, true])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("the player's local status reaches the arbiter before source events of the same tick")
    func playerLocalStatusPrecedesSourceEvents() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "org.videolan.vlc")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.log == ["playerLocal false", "playerLocal true", "+org.videolan.vlc"])
    }

    // MARK: - Owning apps and ignored apps

    @Test("helper processes of one app form a single named source")
    func helpersFormOneSource() async {
        let identifier = StubSourceIdentifier([
            "com.google.Chrome.helper": AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
        ])
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper"), Self.process(2, "com.google.Chrome.helper")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.google.Chrome", isPlaying: true)])
        #expect(h.activeSources.value.last == [AudioSource(id: "com.google.Chrome", name: "Google Chrome")])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.google.Chrome", name: "Google Chrome", state: .playing)])

        // One helper stops: the app keeps playing.
        h.step(after: 0.25, [Self.process(2, "com.google.Chrome.helper")])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.count == 1)
    }

    @Test("an app whose process is gone keeps its name through its stop grace, and is forgotten once it stops")
    func nameKeptThroughStopGrace() async {
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let identifier = StubSourceIdentifier(["com.google.Chrome.helper": chrome])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper")])
        await h.recorder.waitForEvents(count: 1)

        h.step(after: 0.25, []) // its process is gone: the stop grace runs
        #expect(h.activeSources.value.last == [chrome])
        h.step(after: 2)
        await h.recorder.waitForEvents(count: 2)
        #expect(h.activeSources.value.last == [])
        #expect(h.monitor.queue.sync { h.monitor.knownSources }.isEmpty)
    }

    @Test("a process owned by an excluded app (the player's helper) is never a source")
    func excludedOwnerIsIgnored() async {
        let identifier = StubSourceIdentifier([
            "\(TestPlayer.bundleID).helper": AudioSource(id: TestPlayer.bundleID, name: "Jukebox"),
        ])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "\(TestPlayer.bundleID).helper")])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.isEmpty ?? true)
    }

    @Test("a command-line player (afplay run in Terminal) counts as the app that owns it")
    func commandLinePlayerCountsAsItsOwner() async {
        let terminal = AudioSource(id: "com.apple.Terminal", name: "Terminal")
        let identifier = StubSourceIdentifier([:], ownersOfPrograms: [1001: terminal])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.apple.Terminal", isPlaying: true)])
        #expect(h.activeSources.value.last == [terminal])
    }

    @Test("a process without a bundle ID that no app owns (a system daemon) never counts")
    func ownerlessProgramIsIgnored() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: StubSourceIdentifier([:]))
        h.start()
        h.step([Self.process(1, "")])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.isEmpty ?? true)
        #expect(h.monitor.activeAudioReport().isEmpty)
    }

    @Test("an ignored app is published as playing but never reaches the arbiter")
    func ignoredAppIsPublishedNotForwarded() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, ignored: ["org.videolan.vlc"])
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.25)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.map(\.id) == ["org.videolan.vlc"])
        #expect(h.monitor.activeAudioReport() == [.init(id: "org.videolan.vlc", state: .playing, isIgnored: true)])
    }

    @Test("ignoring a playing app stops it for the arbiter; un-ignoring starts it again")
    func togglingIgnoreEmitsEvents() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc"), Self.process(2, "com.apple.Safari")])
        await h.recorder.waitForEvents(count: 2)

        h.monitor.setIgnoredSources(["org.videolan.vlc"])
        await h.recorder.waitForEvents(count: 3)
        h.monitor.setIgnoredSources([])
        await h.recorder.waitForEvents(count: 4)

        #expect(Array(await h.recorder.events.suffix(2)) == [
            .init(bundleID: "org.videolan.vlc", isPlaying: false),
            .init(bundleID: "org.videolan.vlc", isPlaying: true),
        ])
        // It played all along: not heard just now, so its start says nothing of when.
        #expect(Array(await h.recorder.heardSince.suffix(2)) == [nil, nil])
    }

    @Test("an ignored app that stops playing sends nothing to the arbiter")
    func ignoredAppStoppingIsSilent() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), meter: false, ignored: ["org.videolan.vlc"])
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.25, [])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.map(\.id) == [])
    }

    // MARK: - Filtering

    @Test("excluded bundle IDs are never forwarded")
    func excludedBundleIDIsNotForwarded() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.coreaudiod")])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("the monitor's own process is ignored")
    func ownProcessIsIgnored() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([AudioProcessInfo(objectID: 1, bundleID: "com.example.self", pid: getpid())])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("a bundle stays active while any of its processes is audible")
    func sameBundleMultipleProcesses() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0))
        h.start()
        h.step([Self.process(1, "com.apple.Safari"), Self.process(2, "com.apple.Safari")], peaks: [1: 0.3, 2: 0.3])
        await h.recorder.waitForEvents(count: 1)
        h.step(after: 0.25, peaks: [1: 0, 2: 0.3])
        h.step(after: 0.25, peaks: [1: 0, 2: 0])
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.apple.Safari", isPlaying: true),
            .init(bundleID: "com.apple.Safari", isPlaying: false),
        ])
    }
}
