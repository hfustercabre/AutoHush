/// One of its AppleScript commands, as AutoHush sends it: by its code
/// ("spfyPaus"), named in the report as its dictionary names it ("pause").
/// `pauses`: sent to pause it (a toggle is sent both ways).
struct ScriptCommand: Equatable {
    let code: String
    let name: String
    let pauses: Bool
}
