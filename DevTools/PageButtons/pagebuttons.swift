// pagebuttons <app> list [prefix…] | press <label> | press-prefix <prefix> [--lowest]
// Lists or presses the buttons of the web pages in an app's windows (Safari,
// a Safari web app), through Accessibility, the way AutoHush reads them.
// <app> is a name, a bundle ID or a process ID. With --links, links count
// as buttons too; with --path, each listed button shows what surrounds it.
// See README.md.
// Build: swiftc -O -o pagebuttons pagebuttons.swift
import AppKit
import ApplicationServices

func value(_ attribute: String, _ element: AXUIElement) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
}
func string(_ attribute: String, _ element: AXUIElement) -> String { (value(attribute, element) as? String) ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] {
    (value(kAXChildrenAttribute, element) as? [AnyObject] ?? []).map { $0 as! AXUIElement }
}
/// The name AutoHush reads: the description, else the title. Without
/// either, the text inside, marked as such: AutoHush sees no name there.
func label(_ element: AXUIElement) -> (name: String, isTextInside: Bool) {
    if let name = [string(kAXDescriptionAttribute, element), string(kAXTitleAttribute, element)].first(where: { !$0.isEmpty }) {
        return (name, false)
    }
    return (children(element).map { string(kAXValueAttribute, $0) }.joined(), true)
}
func frame(_ element: AXUIElement) -> CGRect? {
    var origin = CGPoint.zero, size = CGSize.zero
    guard let position = value(kAXPositionAttribute, element), let extent = value(kAXSizeAttribute, element) else { return nil }
    AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    AXValueGetValue(extent as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

/// The app's windows on the current desktop, else on any desktop (a private
/// function, `_AXUIElementCreateWithRemoteToken`, as in AutoHush).
func windows(of pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    let shown = (value(kAXWindowsAttribute, app) as? [AnyObject] ?? []).map { $0 as! AXUIElement }
    if !shown.isEmpty { return shown }
    typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { return [] }
    let create = unsafeBitCast(symbol, to: Create.self)
    var token = Data(count: 20)
    token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
    token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
    var found: [AXUIElement] = []
    let deadline = Date().addingTimeInterval(1)
    for number: UInt64 in 0..<1000 where Date() < deadline {
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: number) { Data($0) })
        guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
        AXUIElementSetMessagingTimeout(element, 0.3)
        if string(kAXRoleAttribute, element) == kAXWindowRole { found.append(element) }
    }
    return found
}

/// What surrounds a button, its parent first, up to the page: each
/// element's role (and subrole), its first CSS class, and "slider" when a
/// slider or progress bar is inside it, as a player's controls have.
func surroundings(of element: AXUIElement) -> String {
    var parts: [String] = []
    var current = value(kAXParentAttribute, element).map { $0 as! AXUIElement }
    while let parent = current, parts.count < 10 {
        let role = string(kAXRoleAttribute, parent)
        if role == "AXWebArea" { break }
        let subrole = string(kAXSubroleAttribute, parent)
        let firstClass = (value("AXDOMClassList", parent) as? [String])?.first.map { " ." + $0 } ?? ""
        let slider = holdsSlider(parent) ? " [slider]" : ""
        parts.append(role + (subrole.isEmpty ? "" : "(\(subrole))") + firstClass + slider)
        current = value(kAXParentAttribute, parent).map { $0 as! AXUIElement }
    }
    return parts.joined(separator: " < ")
}

func holdsSlider(_ element: AXUIElement, depth: Int = 0) -> Bool {
    let role = string(kAXRoleAttribute, element)
    if role == "AXSlider" || role == "AXProgressIndicator" { return true }
    return depth < 6 && children(element).contains { holdsSlider($0, depth: depth + 1) }
}

func webAreas(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if string(kAXRoleAttribute, element) == "AXWebArea" { return [element] }
    return depth < 16 ? children(element).flatMap { webAreas(in: $0, depth: depth + 1) } : []
}

struct Button {
    let element: AXUIElement
    let label: String
    let isTextInside: Bool
    /// `nil` without a frame: probably hidden.
    let fromBottom: Double?
    let enabled: Bool

    var place: String { fromBottom.map { String(format: "%.0f pt from the bottom", $0) } ?? "no frame" }
}

let arguments = CommandLine.arguments
let withLinks = arguments.contains("--links")
let withPath = arguments.contains("--path")
let lowest = arguments.contains("--lowest")
let plain = arguments.filter { !$0.hasPrefix("--") }
guard plain.count >= 3 else {
    print("usage: pagebuttons <app> list [prefix…] | press <label> | press-prefix <prefix> [--lowest] [--links]")
    exit(2)
}
let target = plain[1]
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == target || $0.bundleIdentifier == target || String($0.processIdentifier) == target
}) else { print("\(target) isn't running"); exit(1) }
guard AXIsProcessTrusted() else { print("Accessibility isn't allowed for this process"); exit(1) }

var buttons: [Button] = []
let keys = ["AXButtonSearchKey"] + (withLinks ? ["AXLinkSearchKey"] : [])
for window in windows(of: app.processIdentifier) {
    AXUIElementSetMessagingTimeout(window, 0.5)
    guard let windowFrame = frame(window) else { continue }
    for area in webAreas(in: window) {
        for key in keys {
            let search: [String: Any] = ["AXSearchKey": key, "AXResultsLimit": 2000, "AXDirection": "AXDirectionNext",
                                         "AXVisibleOnly": false, "AXImmediateDescendantsOnly": false]
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(area, "AXUIElementsForSearchPredicate" as CFString,
                                                             search as CFDictionary, &result) == .success else { continue }
            for element in (result as? [AnyObject] ?? []).map({ $0 as! AXUIElement }) {
                AXUIElementSetMessagingTimeout(element, 0.5)
                let (name, isTextInside) = label(element)
                buttons.append(Button(element: element, label: name, isTextInside: isTextInside,
                                      fromBottom: frame(element).map { Double(windowFrame.maxY - $0.midY) },
                                      enabled: (value(kAXEnabledAttribute, element) as? Bool) ?? false))
            }
        }
    }
}

func press(_ button: Button) {
    let result = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
    print("pressed \"\(button.label)\" (\(button.place)): \(result == .success ? "ok" : "error \(result.rawValue)")")
}

/// The lowest (or highest) of these buttons. One without a frame, probably
/// hidden, only when none has one.
func pick(_ matching: [Button], lowest: Bool) -> Button? {
    let framed = matching.filter { $0.fromBottom != nil }
    let pool = framed.isEmpty ? matching : framed
    let below: (Button, Button) -> Bool = { ($0.fromBottom ?? 0) < ($1.fromBottom ?? 0) }
    return lowest ? pool.min(by: below) : pool.max(by: below)
}

switch plain[2] {
case "list":
    let prefixes = Array(plain.dropFirst(3))
    print("\(buttons.count) buttons")
    for button in buttons where prefixes.isEmpty || prefixes.contains(where: { button.label.hasPrefix($0) }) {
        let notes = (button.enabled ? "" : " | disabled") + (button.isTextInside ? " | text inside: AutoHush sees no name" : "")
        print("  \(button.label) | \(button.place)\(notes)")
        if withPath { print("      < " + surroundings(of: button.element)) }
    }
case "press":
    guard plain.count > 3, let button = pick(buttons.filter({ $0.label == plain[3] }), lowest: true) else {
        print("no button \"\(plain.count > 3 ? plain[3] : "")\""); exit(1)
    }
    press(button)
case "press-prefix":
    let matching = buttons.filter { plain.count > 3 && $0.label.hasPrefix(plain[3]) && $0.label != plain[3] }
    guard let button = pick(matching, lowest: lowest) else {
        print("no button starting with \"\(plain.count > 3 ? plain[3] : "")\""); exit(1)
    }
    press(button)
default:
    print("unknown command \(plain[2])"); exit(2)
}
