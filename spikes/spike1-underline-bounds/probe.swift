// Spike 1 — underline positioning probe.
// Reads the frontmost app's focused AX element and measures whether
// kAXBoundsForRangeParameterizedAttribute returns usable per-range screen bounds.
// Read-only: never writes to any attribute. Emits one JSON object on stdout.

import AppKit
import ApplicationServices

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, attr as CFString, &out)
    return err == .success ? out : nil
}

func axString(_ el: AXUIElement, _ attr: String) -> String? {
    axValue(el, attr) as? String
}

func rectForRange(_ el: AXUIElement, loc: Int, len: Int) -> (CGRect?, AXError) {
    var range = CFRange(location: loc, length: len)
    guard let rangeVal = AXValueCreate(.cfRange, &range) else { return (nil, .failure) }
    var out: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(
        el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeVal, &out)
    guard err == .success, let v = out, CFGetTypeID(v) == AXValueGetTypeID() else {
        return (nil, err)
    }
    var rect = CGRect.zero
    AXValueGetValue(v as! AXValue, .cgRect, &rect)
    return (rect, err)
}

// Chromium/WebKit path: plain AXBoundsForRange often returns a zero rect there;
// text markers are the API that actually works (this is what Grammarly uses).
func markerBounds(_ el: AXUIElement, loc: Int, len: Int) -> CGRect? {
    var m1: CFTypeRef?
    var m2: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
            el, "AXTextMarkerForIndex" as CFString, NSNumber(value: loc), &m1) == .success,
          let a = m1,
          AXUIElementCopyParameterizedAttributeValue(
            el, "AXTextMarkerForIndex" as CFString, NSNumber(value: loc + len), &m2) == .success,
          let b = m2 else { return nil }
    var rangeRef: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
            el, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
            [a, b] as CFArray, &rangeRef) == .success,
          let range = rangeRef else { return nil }
    var boundsRef: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
            el, "AXBoundsForTextMarkerRange" as CFString, range, &boundsRef) == .success,
          let bv = boundsRef, CFGetTypeID(bv) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    AXValueGetValue(bv as! AXValue, .cgRect, &rect)
    return (rect.width > 0 || rect.height > 0) ? rect : nil
}

func jsonEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
}

guard AXIsProcessTrusted() else {
    print(#"{"error":"ax_not_trusted"}"#)
    exit(2)
}

let front = NSWorkspace.shared.frontmostApplication
let appName = front?.localizedName ?? "unknown"
let bundleID = front?.bundleIdentifier ?? "unknown"
guard let pid = front?.processIdentifier else {
    print(#"{"error":"no_frontmost_app"}"#)
    exit(1)
}

let appEl = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(appEl, 2.0)

guard let focusedRef = axValue(appEl, kAXFocusedUIElementAttribute) else {
    print(#"{"app":"\#(jsonEscape(appName))","bundle":"\#(bundleID)","error":"no_focused_element"}"#)
    exit(0)
}
let focused = focusedRef as! AXUIElement
AXUIElementSetMessagingTimeout(focused, 2.0)

let role = axString(focused, kAXRoleAttribute) ?? "?"
let subrole = axString(focused, kAXSubroleAttribute) ?? ""

var charCount = -1
if let n = axValue(focused, kAXNumberOfCharactersAttribute) as? Int { charCount = n }
let value = axString(focused, kAXValueAttribute)
if charCount < 0, let v = value { charCount = v.count }

var paramAttrs: [String] = []
var namesRef: CFArray?
if AXUIElementCopyParameterizedAttributeNames(focused, &namesRef) == .success,
   let names = namesRef as? [String] { paramAttrs = names }
let advertisesBounds = paramAttrs.contains(kAXBoundsForRangeParameterizedAttribute as String)

// Probe several ranges across the existing text (read-only).
var probes: [String] = []
var usableCount = 0
var distinctRects = Set<String>()
if charCount > 0 {
    let starts = [0, max(0, charCount / 2), max(0, charCount - 2)]
    for (i, loc) in Set(starts).sorted().enumerated() {
        let len = min(2, charCount - loc)
        guard len > 0 else { continue }
        let t0 = Date()
        var method = "range"
        var (rect, err) = rectForRange(focused, loc: loc, len: len)
        if rect == nil || (rect!.width == 0 && rect!.height == 0) {
            if let mr = markerBounds(focused, loc: loc, len: len) {
                rect = mr
                method = "marker"
            }
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let r = rect, r.width > 0 || r.height > 0 {
            usableCount += 1
            distinctRects.insert("\(Int(r.origin.x)),\(Int(r.origin.y))")
            probes.append(
                #"{"range":[\#(loc),\#(len)],"rect":[\#(Int(r.origin.x)),\#(Int(r.origin.y)),\#(Int(r.width)),\#(Int(r.height))],"method":"\#(method)","ms":\#(ms)}"#)
        } else {
            probes.append(#"{"range":[\#(loc),\#(len)],"err":\#(err.rawValue),"ms":\#(ms)}"#)
        }
        _ = i
    }
}

// Distinct origins across different ranges prove per-range (not whole-element) bounds.
let perRange = usableCount >= 2 && distinctRects.count >= 2

let preview = value.map { String($0.prefix(40)) } ?? ""
print("""
{"app":"\(jsonEscape(appName))","bundle":"\(bundleID)","role":"\(role)","subrole":"\(subrole)",\
"chars":\(charCount),"value_readable":\(value != nil),\
"advertises_bounds_for_range":\(advertisesBounds),\
"param_attrs":[\(paramAttrs.map { "\"\(jsonEscape($0))\"" }.joined(separator: ","))],\
"probes":[\(probes.joined(separator: ","))],\
"usable_rects":\(usableCount),"distinct_origins":\(distinctRects.count),\
"per_range_bounds":\(perRange),\
"value_preview":"\(jsonEscape(preview))"}
""")
