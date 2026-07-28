// Diagnostic: dump role tree of the frontmost app's front window.
import AppKit
import ApplicationServices

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var out: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &out) == .success ? out : nil
}
func axString(_ el: AXUIElement, _ attr: String) -> String? { axValue(el, attr) as? String }

func dump(_ el: AXUIElement, depth: Int, budget: inout Int) {
    guard depth < 30, budget > 0 else { return }
    budget -= 1
    AXUIElementSetMessagingTimeout(el, 2.0)
    let role = axString(el, kAXRoleAttribute) ?? "?"
    let sub = axString(el, kAXSubroleAttribute) ?? ""
    var chars = -1
    if let n = axValue(el, kAXNumberOfCharactersAttribute) as? Int { chars = n }
    let desc = axString(el, kAXDescriptionAttribute) ?? ""
    let indent = String(repeating: "  ", count: depth)
    print("\(indent)\(role)\(sub.isEmpty ? "" : "/\(sub)")\(chars >= 0 ? " chars=\(chars)" : "")\(desc.isEmpty ? "" : " desc=\(desc.prefix(30))")")
    guard let cRef = axValue(el, kAXChildrenAttribute), let children = cRef as? [AXUIElement] else { return }
    for child in children { dump(child, depth: depth + 1, budget: &budget) }
}

guard AXIsProcessTrusted() else { print("not trusted"); exit(2) }
guard let front = NSWorkspace.shared.frontmostApplication else { exit(1) }
print("app: \(front.localizedName ?? "?")")
let appEl = AXUIElementCreateApplication(front.processIdentifier)
AXUIElementSetMessagingTimeout(appEl, 2.0)
var windowsRef: CFTypeRef?
if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
   let windows = windowsRef as? [AXUIElement], let w = windows.first {
    var budget = 800
    dump(w, depth: 0, budget: &budget)
}
