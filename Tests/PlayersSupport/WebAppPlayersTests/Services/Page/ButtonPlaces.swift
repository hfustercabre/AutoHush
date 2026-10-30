import Foundation
@testable import WebAppPlayers

/// Places used by the tests: a player bar at the bottom, the page's main part higher up.
enum ButtonPlaces {
    static let playerBar = ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkComplementary"], distanceFromBottom: 40)
    static let main = ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain"], distanceFromBottom: 600)
    static let fullScreen = ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain", "AXGroup"], distanceFromBottom: 300)
}
