import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AutoPauseIntents")
@MainActor
struct AutoPauseIntentsTests {
    /// A moment well ahead of the real one, so the settings never clear a
    /// "turn off for" made here as expired on their own.
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)

    @Test("Set Auto-Pause's choices turn it on, off, or to the other")
    func operations() {
        let settings = UserSettings(preferences: Preferences(store: InMemoryPreferenceStore()), now: now)
        #expect(settings.isAutoPauseActive)

        AutoPauseOperation.turnOff.apply(to: settings, now: now)
        #expect(!settings.isAutoPauseActive)
        #expect(settings.autoPauseSetting == AutoPauseSetting(isEnabled: false, snoozedUntil: nil))

        // On also ends a "turn off for", as the menu's switch does.
        settings.snooze(.thirtyMinutes, now: now)
        #expect(!settings.isAutoPauseActive)
        AutoPauseOperation.turnOn.apply(to: settings, now: now)
        #expect(settings.isAutoPauseActive)
        #expect(settings.autoPauseSetting == AutoPauseSetting())

        AutoPauseOperation.toggle.apply(to: settings, now: now)
        #expect(!settings.isAutoPauseActive)
        AutoPauseOperation.toggle.apply(to: settings, now: now)
        #expect(settings.isAutoPauseActive)
        #expect(settings.autoPauseSetting == AutoPauseSetting())
    }

    @Test("each duration is the menu's 'turn off for' of the same name")
    func durations() {
        #expect(AutoPauseDuration.allCases.count == 5)
        #expect(AutoPauseSnooze.allCases.count == 5)
        for duration in AutoPauseDuration.allCases {
            #expect("\(duration.snooze)" == duration.rawValue)
        }
        // Every snooze has its duration, in the menu's order.
        #expect(AutoPauseDuration.allCases.map(\.snooze) == AutoPauseSnooze.allCases)
    }

    @Test("the choices' lists keep their order and start on Off and 15 Minutes")
    func options() async throws {
        #expect(try await AutoPauseOperationOptions().results() == [.turnOn, .turnOff, .toggle])
        #expect(await AutoPauseOperationOptions().defaultResult() == .turnOff)
        #expect(try await AutoPauseDurationOptions().results()
                == [.fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .twentyFourHours])
        #expect(await AutoPauseDurationOptions().defaultResult() == .fifteenMinutes)
    }

    @Test("the durations' titles are the menu's keys, so their translations are reused")
    func titlesReuseTheMenu() {
        #expect(AutoPauseDuration.caseDisplayRepresentations.count == AutoPauseDuration.allCases.count)
        for duration in AutoPauseDuration.allCases {
            let title = AutoPauseDuration.caseDisplayRepresentations[duration]?.title
            #expect(title?.key == duration.snooze.title)
        }
    }
}
