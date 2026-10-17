import SwiftUI
import AutoHushKit

/// The width of the menu's panel: 345 pt, or more when AntiDot mode's ways
/// (`ChoiceChips`, small) need it in the app's language, with More Settings'
/// margins around them (8 pt for its part, 10 for the choice, a side).
@MainActor let menuContentWidth: CGFloat = max(345, ChoiceChips<Never>.fittingWidth(
    [DetectionMethod.playbackSignals, .openStreams].map(\.title), size: .small) + 2 * (8 + 10))
