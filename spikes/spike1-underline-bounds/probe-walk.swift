// Variant of probe.swift: walks the frontmost app's front window tree and probes
// every text-bearing element (AXTextArea/AXTextField/editable web area) it finds.
// Read-only. One JSON object per probed element, one per line.

import AppKit
import ApplicationServices

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &out) == .success ? out : nil
}
func axString(_ el: AXUIElement, _ attr: String) -> String? { axValue(el, attr) as? String }

func rectForRange(_ el: AXUIElement, loc: Int, len: Int) -> (CGRect?, AXError) {
    var range = CFRange(location: loc, length: len)
    guard let rangeVal = AXValueCreate(.cfRange, &range) else { return (nil, .failure) }
    var out: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(
        el, kAXBoundsForRangeParameterizedAttribute as CFString, rangeVal, &out)
    guard err == .success, let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return (nil, err) }
    var rect = CGRect.zero
    AXValueGetValue(v as! AXValue, .cgRect, &rect)
    return (rect, err)
}

func jsonEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
}

func probeElement(_ el: AXUIElement, path: String, force: Bool = false) {
    let role = axString(el, kAXRoleAttribute) ?? "?"
    var charCount = -1
    if let n = axValue(el, kAXNumberOfCharactersAttribute) as? Int { charCount = n }
    let value = axString(el, kAXValueAttribute)
    if charCount < 0, let v = value { charCount = v.count }
    guard charCount > 0 || force else { return }

    var paramAttrs: [String] = []
    var namesRef: CFArray?
    if AXUIElementCopyParameterizedAttributeNames(el, &namesRef) == .success,
       let names = namesRef as? [String] { paramAttrs = names }
    let advertises = paramAttrs.contains(kAXBoundsForRangeParameterizedAttribute as String)

    var probes: [String] = []
    var usable = 0
    var origins = Set<String>()
    for loc in Set([0, max(0, charCount / 2), max(0, charCount - 2)]).sorted() {
        let len = min(2, charCount - loc)
        guard len > 0 else { continue }
        let t0 = Date()
        let (rect, err) = rectForRange(el, loc: loc, len: len)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let r = rect, r.width > 0 || r.height > 0 {
            usable += 1
            origins.insert("\(Int(r.origin.x)),\(Int(r.origin.y))")
            probes.append(#"{"range":[\#(loc),\#(len)],"rect":[\#(Int(r.origin.x)),\#(Int(r.origin.y)),\#(Int(r.width)),\#(Int(r.height))],"ms":\#(ms)}"#)
        } else {
            probes.append(#"{"range":[\#(loc),\#(len)],"err":\#(err.rawValue),"ms":\#(ms)}"#)
        }
    }
    let preview = value.map { String($0.prefix(40)) } ?? ""
    print("""
    {"path":"\(jsonEscape(path))","role":"\(role)","chars":\(charCount),\
    "advertises_bounds_for_range":\(advertises),\
    "probes":[\(probes.joined(separator: ","))],\
    "per_range_bounds":\(usable >= 2 && origins.count >= 2),\
    "value_preview":"\(jsonEscape(preview))"}
    """)
}

let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXWebArea", "AXComboBox", "AXStaticText"]

func walk(_ el: AXUIElement, depth: Int, path: String, budget: inout Int) {
    guard depth < 25, budget > 0 else { return }
    budget -= 1
    AXUIElementSetMessagingTimeout(el, 2.0)
    let role = axString(el, kAXRoleAttribute) ?? "?"
    if role == "AXWebArea" {
        probeElement(el, path: "\(path)/\(role)", force: true)
    } else if textRoles.contains(role) {
        probeElement(el, path: "\(path)/\(role)")
    }
    guard let childrenRef = axValue(el, kAXChildrenAttribute),
          let children = childrenRef as? [AXUIElement] else { return }
    for (i, child) in children.enumerated() {
        walk(child, depth: depth + 1, path: "\(path)/\(role)[\(i)]", budget: &budget)
    }
}

guard AXIsProcessTrusted() else { print(#"{"error":"ax_not_trusted"}"#); exit(2) }
guard let front = NSWorkspace.shared.frontmostApplication else {
    print(#"{"error":"no_frontmost_app"}"#); exit(1)
}
let appEl = AXUIElementCreateApplication(front.processIdentifier)
AXUIElementSetMessagingTimeout(appEl, 2.0)
print(#"{"app":"\#(jsonEscape(front.localizedName ?? "?"))","bundle":"\#(front.bundleIdentifier ?? "?")"}"#)

if CommandLine.arguments.contains("--from-focused") {
    guard let focusedRef = axValue(appEl, kAXFocusedUIElementAttribute) else {
        print(#"{"error":"no_focused_element"}"#); exit(0)
    }
    var budget = 2000
    walk(focusedRef as! AXUIElement, depth: 0, path: "focused", budget: &budget)
} else {
    var windowsRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
       let windows = windowsRef as? [AXUIElement] {
        var budget = 4000
        for (i, w) in windows.prefix(3).enumerated() {
            let title = axString(w, kAXTitleAttribute) ?? ""
            print(#"{"window":\#(i),"title":"\#(jsonEscape(title))"}"#)
            walk(w, depth: 0, path: "w\(i)", budget: &budget)
        }
    } else {
        print(#"{"error":"no_windows"}"#)
    }
}
