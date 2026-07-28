// Chromium marker-stepping probe: AXTextMarkerRangeForUIElement -> start marker
// (SPI) -> AXNextTextMarkerForTextMarker xN -> AXBoundsForTextMarkerRange.
// Validates every range with AXStringForTextMarkerRange. Read-only.

import AppKit
import ApplicationServices

typealias RangeCopyMarkerFn = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
let handle = dlopen(
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
func lookup(_ name: String) -> RangeCopyMarkerFn? {
    guard let h = handle, let sym = dlsym(h, name) else { return nil }
    return unsafeBitCast(sym, to: RangeCopyMarkerFn.self)
}
guard let copyStartMarker = lookup("AXTextMarkerRangeCopyStartMarker") else {
    print("SPI unavailable"); exit(3)
}

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &out) == .success ? out : nil
}
func param(_ el: AXUIElement, _ attr: String, _ p: CFTypeRef) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyParameterizedAttributeValue(el, attr as CFString, p, &out) == .success
        ? out : nil
}

guard AXIsProcessTrusted() else { print("not trusted"); exit(2) }
let targetName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let front: NSRunningApplication
if let name = targetName {
    guard let match = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
        print("app not running: \(name)"); exit(1)
    }
    front = match
} else {
    guard let f = NSWorkspace.shared.frontmostApplication else { exit(1) }
    front = f
}
print("app: \(front.localizedName ?? "?")")

let appEl = AXUIElementCreateApplication(front.processIdentifier)
AXUIElementSetMessagingTimeout(appEl, 2.0)
guard let focusedRef = axValue(appEl, kAXFocusedUIElementAttribute) else {
    print("no focused element"); exit(0)
}
let focused = focusedRef as! AXUIElement
AXUIElementSetMessagingTimeout(focused, 2.0)

let chars = (axValue(focused, kAXNumberOfCharactersAttribute) as? Int)
    ?? (axValue(focused, kAXValueAttribute) as? String)?.count ?? 0
print("focused chars: \(chars)")

guard let elRange = param(focused, "AXTextMarkerRangeForUIElement", focused) else {
    print("no AXTextMarkerRangeForUIElement"); exit(0)
}
if let s = param(focused, "AXStringForTextMarkerRange", elRange) as? String {
    print("element range text: \"\(s.prefix(70))\"")
}
guard let start = copyStartMarker(elRange)?.takeRetainedValue() else {
    print("no start marker"); exit(0)
}

// Build a marker per character offset by stepping.
let t0 = Date()
var markers: [CFTypeRef] = [start]
var cur: CFTypeRef = start
for _ in 0..<min(chars, 300) {
    guard let next = param(focused, "AXNextTextMarkerForTextMarker", cur) else { break }
    markers.append(next)
    cur = next
}
let stepMs = Int(Date().timeIntervalSince(t0) * 1000)
print("stepped \(markers.count - 1) markers in \(stepMs) ms")

for loc in Set([0, max(0, chars / 2), max(0, chars - 2)]).sorted() where chars > 0 {
    let len = min(2, chars - loc)
    guard len > 0, loc + len < markers.count else { continue }
    let t1 = Date()
    guard let range = param(focused, "AXTextMarkerRangeForUnorderedTextMarkers",
                            [markers[loc], markers[loc + len]] as CFArray) else {
        print("range [\(loc),\(len)]: no marker range"); continue
    }
    let text = (param(focused, "AXStringForTextMarkerRange", range) as? String) ?? "?"
    guard let bv = param(focused, "AXBoundsForTextMarkerRange", range),
          CFGetTypeID(bv) == AXValueGetTypeID() else {
        print("range [\(loc),\(len)]: no bounds"); continue
    }
    var rect = CGRect.zero
    AXValueGetValue(bv as! AXValue, .cgRect, &rect)
    let ms = Int(Date().timeIntervalSince(t1) * 1000)
    print("range [\(loc),\(len)] \"\(text)\": rect \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height)) (\(ms) ms)")
}
