// Chromium text-marker probe: resolves the focused element's position in the
// web area's global text-marker space, then asks for per-range bounds there.
// Uses the HIServices AXTextMarkerRange accessors via dlsym (same route
// commercial AX overlay tools use). Read-only.

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
let copyEndMarker = lookup("AXTextMarkerRangeCopyEndMarker")

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &out) == .success ? out : nil
}
func param(_ el: AXUIElement, _ attr: String, _ p: CFTypeRef) -> CFTypeRef? {
    var out: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(el, attr as CFString, p, &out)
    return err == .success ? out : nil
}

guard AXIsProcessTrusted() else { print("not trusted"); exit(2) }
guard let front = NSWorkspace.shared.frontmostApplication else { exit(1) }
print("app: \(front.localizedName ?? "?")")
guard copyStartMarker != nil, copyEndMarker != nil else {
    print("SPI unavailable: AXTextMarkerRangeCopyStartMarker not found")
    exit(3)
}

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

// 1. Marker range covering the focused element (asked of the element itself).
guard let markerRange = param(focused, "AXTextMarkerRangeForUIElement", focused) else {
    print("no AXTextMarkerRangeForUIElement"); exit(0)
}
guard let startMarker = copyStartMarker!(markerRange)?.takeRetainedValue() else {
    print("could not extract start marker"); exit(0)
}

// 2. Global index of the element's first character.
guard let idxRef = param(focused, "AXIndexForTextMarker", startMarker),
      let globalStart = (idxRef as? NSNumber)?.intValue else {
    print("no AXIndexForTextMarker"); exit(0)
}
print("global start index: \(globalStart)")

// 3. Per-range bounds via markers at global indices.
for loc in Set([0, max(0, chars / 2), max(0, chars - 2)]).sorted() where chars > 0 {
    let len = min(2, chars - loc)
    guard len > 0 else { continue }
    let t0 = Date()
    guard let m1 = param(focused, "AXTextMarkerForIndex", NSNumber(value: globalStart + loc)),
          let m2 = param(focused, "AXTextMarkerForIndex", NSNumber(value: globalStart + loc + len)),
          let range = param(focused, "AXTextMarkerRangeForUnorderedTextMarkers", [m1, m2] as CFArray),
          let bv = param(focused, "AXBoundsForTextMarkerRange", range),
          CFGetTypeID(bv) == AXValueGetTypeID() else {
        print("range [\(loc),\(len)]: marker chain failed")
        continue
    }
    var rect = CGRect.zero
    AXValueGetValue(bv as! AXValue, .cgRect, &rect)
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    print("range [\(loc),\(len)]: rect \(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height)) (\(ms) ms)")
}
