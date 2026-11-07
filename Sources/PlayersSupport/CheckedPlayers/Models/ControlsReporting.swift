/// A player that says what controls it (`PlayerControls`).
package protocol ControlsReporting: Sendable {
    var controls: PlayerControls { get }
}
