// Passive probe: finds a text element by value substring in a named app's
// windows (no activation, no focus change), then measures bounds via plain
// AXBoundsForRange and the marker-stepping path. Read-only.
// Usage: probe-find <AppName> <value-substring>

import AppKit
import ApplicationServices

typealias RangeCopyMarkerFn = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
let handle = dlopen(
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
func lookup(_ name: String) -> RangeCopyMarkerFn? {
    guard let h = handle, let sym = dlsym(h, name) else { return nil }
    return unsafeBitCast(sym, to: RangeCopyMarkerFn.self)
}
let copyStartMarker = lookup("AXTextMarkerRangeCopyStartMarker")

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &out) == .success ? out : nil
}
func axString(_ el: AXUIElement, _ attr: String) -> String? { axValue(el, attr) as? String }
func param(_ el: AXUIElement, _ attr: String, _ p: CFTypeRef) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyParameterizedAttributeValue(el, attr as CFString, p, &out) == .success
        ? out : nil
}

func plainBounds(_ el: AXUIElement, loc: Int, len: Int) -> CGRect? {
    var range = CFRange(location: loc, length: len)
    guard let rv = AXValueCreate(.cfRange, &range) else { return nil }
    var out: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
            el, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &out) == .success,
          let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    AXValueGetValue(v as! AXValue, .cgRect, &rect)
    return (rect.width > 0 || rect.height > 0) ? rect : nil
}

guard AXIsProcessTrusted() else { print("not trusted"); exit(2) }
guard CommandLine.arguments.count >= 3 else { print("usage: probe-find <App> <substring>"); exit(1) }
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
        if let v = axString(el, kAXValueAttribute), v.contains(needle) {
            found = el
            return
        }
    }
    guard let cRef = axValue(el, kAXChildrenAttribute), let children = cRef as? [AXUIElement] else { return }
    for child in children { search(child, depth: depth + 1, budget: &budget) }
}

var windowsRef: CFTypeRef?
guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement] else {
    print("no windows"); exit(0)
}
var budget = 8000
for w in windows { search(w, depth: 0, budget: &budget); if found != nil { break } }
guard let el = found else { print("element not found (budget left \(budget))"); exit(0) }

let value = axString(el, kAXValueAttribute) ?? ""
let chars = value.count
print("found AXTextArea, \(chars) chars: \"\(value.prefix(50))\"")

for loc in Set([0, max(0, chars / 2), max(0, chars - 2)]).sorted() where chars > 0 {
    let len = min(2, chars - loc)
    guard len > 0 else { continue }
    if let r = plainBounds(el, loc: loc, len: len) {
        print("plain range [\(loc),\(len)]: \(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.width))x\(Int(r.height))")
    } else {
        print("plain range [\(loc),\(len)]: nil/zero")
    }
}

guard let csm = copyStartMarker,
      let elRange = param(el, "AXTextMarkerRangeForUIElement", el),
      let start = csm(elRange)?.takeRetainedValue() else {
    print("marker path unavailable"); exit(0)
}
var markers: [CFTypeRef] = [start]
var cur: CFTypeRef = start
for _ in 0..<min(chars, 300) {
    guard let next = param(el, "AXNextTextMarkerForTextMarker", cur) else { break }
    markers.append(next)
    cur = next
}
for loc in Set([0, max(0, chars / 2), max(0, chars - 2)]).sorted() where chars > 0 {
    let len = min(2, chars - loc)
    guard len > 0, loc + len < markers.count else { continue }
    guard let range = param(el, "AXTextMarkerRangeForUnorderedTextMarkers",
                            [markers[loc], markers[loc + len]] as CFArray) else { continue }
    let text = (param(el, "AXStringForTextMarkerRange", range) as? String) ?? "?"
    guard let bv = param(el, "AXBoundsForTextMarkerRange", range),
          CFGetTypeID(bv) == AXValueGetTypeID() else {
        print("marker range [\(loc),\(len)] \"\(text)\": no bounds"); continue
    }
    var rect = CGRect.zero
    AXValueGetValue(bv as! AXValue, .cgRect, &rect)
    print("marker range [\(loc),\(len)] \"\(text)\": \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))")
}
