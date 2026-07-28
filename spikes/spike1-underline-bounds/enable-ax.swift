// Sets AXManualAccessibility=true on the frontmost app (Electron/Chromium apps
// gate their full accessibility tree behind this or AT detection).
import AppKit
import ApplicationServices

guard let front = NSWorkspace.shared.frontmostApplication else { exit(1) }
let appEl = AXUIElementCreateApplication(front.processIdentifier)
let e1 = AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
let e2 = AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
print("\(front.localizedName ?? "?"): AXManualAccessibility=\(e1.rawValue) AXEnhancedUserInterface=\(e2.rawValue)")
