// Cleanup tool: removes an exact substring from a text element in a named app,
// via kAXSelectedTextRange + kAXSelectedTextAttribute (no focus change, no
// keystrokes). Verifies the anchor before and after. Removes ONLY the given
// substring; refuses if it appears more than once.
// Usage: remove-text <AppName> <exact-substring>

import AppKit
import ApplicationServices

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &out) == .success ? out : nil
}
func axString(_ el: AXUIElement, _ attr: String) -> String? { axValue(el, attr) as? String }

guard AXIsProcessTrusted() else { print("not trusted"); exit(2) }
guard CommandLine.arguments.count >= 3 else { print("usage: remove-text <App> <substring>"); exit(1) }
let appName = CommandLine.arguments[1]
let needle = CommandLine.arguments[2]
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    print("app not running: \(appName)"); exit(1)
}
let appEl = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(appEl, 2.0)

var found: AXUIElement?
func search(_ el: AXUIElement, depth: Int, budget: inout Int) {
    guard depth < 30, budget > 0, found == nil else { return }
    budget -= 1
    AXUIElementSetMessagingTimeout(el, 2.0)
    let role = axString(el, kAXRoleAttribute) ?? "?"
    if role == "AXTextArea" || role == "AXTextField" {
        if let v = axString(el, kAXValueAttribute), v.contains(needle) { found = el; return }
    }
    guard let cRef = axValue(el, kAXChildrenAttribute), let children = cRef as? [AXUIElement] else { return }
    for child in children { search(child, depth: depth + 1, budget: &budget) }
}
var windowsRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement] else { print("no windows"); exit(0) }
var budget = 8000
for w in windows { search(w, depth: 0, budget: &budget); if found != nil { break } }
guard let el = found, let value = axString(el, kAXValueAttribute) else {
    print("element not found"); exit(0)
}

let occurrences = value.components(separatedBy: needle).count - 1
guard occurrences == 1 else { print("refusing: \(occurrences) occurrences"); exit(1) }
guard let r = value.range(of: needle) else { exit(1) }
let loc = value.distance(from: value.startIndex, to: r.lowerBound)

var settable = DarwinBoolean(false)
AXUIElementIsAttributeSettable(el, kAXSelectedTextRangeAttribute as CFString, &settable)
print("selected-range settable: \(settable)")

var cfRange = CFRange(location: loc, length: needle.count)
guard let rangeVal = AXValueCreate(.cfRange, &cfRange) else { exit(1) }
let e1 = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, rangeVal)
let e2 = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, "" as CFString)
print("set range err=\(e1.rawValue), replace err=\(e2.rawValue)")

let after = axString(el, kAXValueAttribute) ?? ""
print(after.contains(needle) ? "FAILED: substring still present" : "removed. value now: \"\(after.prefix(60))\" (\(after.count) chars)")
