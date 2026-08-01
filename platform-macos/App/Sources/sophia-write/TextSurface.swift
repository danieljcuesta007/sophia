// TextSurface — how the agent reads text, positions underlines, and selects
// ranges in the focused element. Two implementations, per Spike 1's measured
// tiers: FlatTextSurface for AppKit/TextKit elements whose kAXValue is the
// document (TextEdit, Notes, Messages, Chrome textareas), and WebKitTextSurface
// for web areas (Mail compose) whose text lives on per-paragraph AXStaticText
// descendants with node-local offsets.
//
// Spike-1 traps enforced here:
// - Chromium reports success with zero rects: validate rects, never error codes.
// - Off-screen ranges return unusable rects: clip to the element's visible frame.
// - Every AX call is deadline-bounded via AXUIElementSetMessagingTimeout.
//
// All ranges are UTF-16 code units (what AX and the Rust core both speak).

import ApplicationServices
import AppKit

// MARK: - small AX helpers

enum AX {
    static let timeout: Float = 0.25

    static func bound(_ el: AXUIElement) {
        AXUIElementSetMessagingTimeout(el, timeout)
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref)
                == .success,
              let arr = ref as? [AXUIElement]
        else { return [] }
        return arr
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef)
                == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef)
                == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
              AXValueGetValue((posRef as! AXValue), .cgPoint, &point),
              AXValueGetValue((sizeRef as! AXValue), .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)  // top-left-origin screen coords
    }

    /// Per-range screen bounds. Returns nil for missing/zero rects — the
    /// Chromium "success with zero rect" trap means the error code is never
    /// trusted on its own.
    static func boundsForRange(_ el: AXUIElement, _ range: NSRange) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let param = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            el, kAXBoundsForRangeParameterizedAttribute as CFString, param, &ref)
                == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue((ref as! AXValue), .cgRect, &rect),
              rect.width > 0.5, rect.height > 0.5
        else { return nil }
        return rect
    }

    static func setSelectedRange(_ el: AXUIElement, _ range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            el, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    static func selectedText(_ el: AXUIElement) -> String? {
        string(el, kAXSelectedTextAttribute)
    }

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        return element(system, kAXFocusedUIElementAttribute)
    }

    static func pid(_ el: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(el, &pid) == .success else { return nil }
        return pid
    }
}

// MARK: - the surface protocol

protocol TextSurface: AnyObject {
    var element: AXUIElement { get }
    /// Full document text, or nil when unreadable.
    func readText() -> String?
    /// Screen rects (top-left origin) for a UTF-16 range; empty when the tier
    /// doesn't support per-range bounds. May span wrapped lines.
    func bounds(for range: NSRange) -> [CGRect]
    /// The element's visible frame for clipping (spike-1 trap 5).
    func visibleFrame() -> CGRect?
    /// Select the range and verify the selection reads back as `expecting`.
    /// False means "could not safely select" — the caller must abandon.
    func select(range: NSRange, expecting: String) -> Bool
}

// MARK: - flat elements (AppKit/TextKit/Chromium textareas)

final class FlatTextSurface: TextSurface {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
        AX.bound(element)
    }

    func readText() -> String? {
        AX.string(element, kAXValueAttribute)
    }

    func bounds(for range: NSRange) -> [CGRect] {
        guard let whole = AX.boundsForRange(element, range) else { return [] }
        // Node-box trap (Spike 1): some hosts return the element's whole frame
        // for any range. A "per-range" rect that fills most of the element is
        // bogus — no underline beats a wrong one.
        if let frame = AX.frame(element),
           whole.width > frame.width * 0.9, whole.height > frame.height * 0.9,
           frame.width > 100 {
            return []
        }
        // An anchor is a few words; a rect taller than a couple of wrapped
        // lines is not text bounds.
        guard whole.height <= 80 else { return [] }
        return [whole]
    }

    func visibleFrame() -> CGRect? {
        AX.frame(element)
    }

    func select(range: NSRange, expecting: String) -> Bool {
        guard AX.setSelectedRange(element, range) else { return false }
        // Readback: success codes lie (spike-1 trap 3) — the selection must
        // prove itself before anything is replaced.
        return AX.selectedText(element) == expecting
    }
}

// MARK: - WebKit web areas (Mail compose)

/// Maps the concatenated text of per-paragraph AXStaticText descendants to the
/// nodes that own it. Offsets inside each node are node-local (spike 1).
final class WebKitTextSurface: TextSurface {
    let element: AXUIElement
    private struct Node {
        let element: AXUIElement
        let start: Int  // UTF-16 offset of this node's text in the document
        let length: Int
    }
    private var nodes: [Node] = []
    private var text = ""

    init(element: AXUIElement) {
        self.element = element
        AX.bound(element)
        rebuild()
    }

    private func rebuild() {
        nodes = []
        text = ""
        var pieces: [String] = []
        var cursor = 0
        walk(element, depth: 0) { node, value in
            let length = value.utf16.count
            self.nodes.append(Node(element: node, start: cursor, length: length))
            pieces.append(value)
            cursor += length + 1  // separator newline between block nodes
        }
        text = pieces.joined(separator: "\n")
    }

    private func walk(_ el: AXUIElement, depth: Int,
                      visit: (AXUIElement, String) -> Void) {
        guard depth < 24 else { return }
        AX.bound(el)
        if AX.string(el, kAXRoleAttribute) == "AXStaticText",
           let value = AX.string(el, kAXValueAttribute), !value.isEmpty {
            visit(el, value)
            return
        }
        for child in AX.children(el) {
            walk(child, depth: depth + 1, visit: visit)
        }
    }

    func readText() -> String? {
        rebuild()
        return text.isEmpty ? nil : text
    }

    func bounds(for range: NSRange) -> [CGRect] {
        var rects: [CGRect] = []
        for node in nodes {
            let nodeRange = NSRange(location: node.start, length: node.length)
            guard let overlap = nodeRange.intersection(range), overlap.length > 0
            else { continue }
            let local = NSRange(
                location: overlap.location - node.start, length: overlap.length)
            if let rect = AX.boundsForRange(node.element, local) {
                rects.append(rect)
            }
        }
        return rects
    }

    func visibleFrame() -> CGRect? {
        AX.frame(element)
    }

    func select(range: NSRange, expecting: String) -> Bool {
        // WebKit web areas do not accept document-offset selection writes
        // against our concatenated indexing — but the per-paragraph
        // AXStaticText NODES might accept node-local ranges (untested in
        // Spike 1; readback decides). When the range sits inside one node,
        // try there first; fall back to the web area. Any failure abandons —
        // the document is never touched on a lie.
        if let node = nodes.first(where: {
            range.location >= $0.start && range.location + range.length <= $0.start + $0.length
        }) {
            let local = NSRange(location: range.location - node.start, length: range.length)
            if AX.setSelectedRange(node.element, local) {
                if AX.selectedText(node.element) == expecting
                    || AX.selectedText(element) == expecting {
                    return true
                }
            }
        }
        guard AX.setSelectedRange(element, range) else { return false }
        return AX.selectedText(element) == expecting
    }
}

// MARK: - factory

enum SurfaceFactory {
    /// Wrap a focused element in the right surface, or nil when the element is
    /// not lintable text (secure fields are refused before this is called).
    static func make(for element: AXUIElement) -> TextSurface? {
        let role = AX.string(element, kAXRoleAttribute) ?? ""
        switch role {
        case "AXTextArea", "AXTextField":
            return FlatTextSurface(element: element)
        case "AXWebArea":
            return WebKitTextSurface(element: element)
        default:
            // Some WebKit hosts focus a descendant; if an ancestor web area
            // exists, use it. Otherwise: not a text surface.
            if let webArea = ancestorWebArea(of: element) {
                return WebKitTextSurface(element: webArea)
            }
            return nil
        }
    }

    private static func ancestorWebArea(of el: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = AX.element(el, kAXParentAttribute)
        var depth = 0
        while let node = current, depth < 12 {
            if AX.string(node, kAXRoleAttribute) == "AXWebArea" { return node }
            current = AX.element(node, kAXParentAttribute)
            depth += 1
        }
        return nil
    }
}
