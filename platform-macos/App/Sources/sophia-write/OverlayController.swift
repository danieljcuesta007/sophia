// OverlayController — borrowed-window underlines (blueprint §13). We cannot
// draw inside another app's text view, so a transparent, click-through,
// non-activating NSWindow floats over the focused element and draws underline
// segments at AX-reported bounds.
//
// AC-27: the window is click-through (ignoresMouseEvents) and absent from the
// AX tree, so VoiceOver hits no phantom elements. Click detection therefore
// happens elsewhere (a global mouse monitor in AppMain), never here.
// AC-28: corrections are solid, style is dotted — distinguishable by style,
// not hue alone. No animation, no sound, no badge counts (§12.4).

import AppKit

struct UnderlineMark {
    let issue: Issue
    let rects: [CGRect]  // screen rects, top-left origin (AX coordinates)
}

final class OverlayController {
    private var window: OverlayWindow?

    /// Correctness ink and style ink (brand green #3F8A4F for style marks).
    static let correctionColor = NSColor(
        calibratedRed: 0.76, green: 0.29, blue: 0.25, alpha: 0.9)
    static let styleColor = NSColor(
        calibratedRed: 0x3F / 255.0, green: 0x8A / 255.0, blue: 0x4F / 255.0, alpha: 0.9)

    private(set) var marks: [UnderlineMark] = []

    func show(marks: [UnderlineMark], clippedTo visible: CGRect?) {
        let clipped = clip(marks, to: visible)
        self.marks = clipped
        guard !clipped.isEmpty else {
            hide()
            return
        }

        let allRects = clipped.flatMap(\.rects)
        let unionAX = allRects.dropFirst().reduce(allRects[0]) { $0.union($1) }
            .insetBy(dx: -4, dy: -6)
        let frame = Self.cocoaRect(fromAX: unionAX)

        let window = ensureWindow()
        window.setFrame(frame, display: false)
        (window.contentView as? UnderlineView)?.render(
            marks: clipped, windowFrame: frame)
        window.orderFrontRegardless()
    }

    func hide() {
        marks = []
        window?.orderOut(nil)
    }

    /// The issue whose underline contains this screen point (AX coords), if any.
    func mark(atAXPoint point: CGPoint) -> UnderlineMark? {
        marks.first { mark in
            mark.rects.contains { $0.insetBy(dx: -2, dy: -3).contains(point) }
        }
    }

    private func clip(_ marks: [UnderlineMark], to visible: CGRect?) -> [UnderlineMark] {
        guard let visible else { return marks }
        // Spike-1 trap 5: scrolled-away text returns unusable rects.
        return marks.compactMap { mark in
            let kept = mark.rects.filter { visible.intersects($0) && $0.minY >= 0 }
            return kept.isEmpty ? nil : UnderlineMark(issue: mark.issue, rects: kept)
        }
    }

    private func ensureWindow() -> OverlayWindow {
        if let window { return window }
        let w = OverlayWindow(
            contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true  // AC-27: click-through, always
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        w.contentView = UnderlineView()
        window = w
        return w
    }

    /// AX reports top-left-origin global coordinates; Cocoa windows use
    /// bottom-left origin of the primary screen.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width, height: rect.height)
    }
}

/// Invisible to accessibility (AC-27) and to key focus.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { nil }
}

private final class UnderlineView: NSView {
    private var segments: [(rect: CGRect, coarse: Issue.Coarse)] = []

    override var isFlipped: Bool { false }
    override func isAccessibilityElement() -> Bool { false }

    func render(marks: [UnderlineMark], windowFrame: CGRect) {
        segments = marks.flatMap { mark in
            mark.rects.map { axRect -> (CGRect, Issue.Coarse) in
                let cocoa = OverlayController.cocoaRect(fromAX: axRect)
                // Window-local coordinates.
                let local = CGRect(
                    x: cocoa.origin.x - windowFrame.origin.x,
                    y: cocoa.origin.y - windowFrame.origin.y,
                    width: cocoa.width, height: cocoa.height)
                return (local, mark.issue.coarse)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (rect, coarse) in segments {
            let path = NSBezierPath()
            let y = rect.minY + 1.5
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            path.lineWidth = 2
            path.lineCapStyle = .round
            switch coarse {
            case .correction:
                OverlayController.correctionColor.setStroke()
            case .style:
                OverlayController.styleColor.setStroke()
                let pattern: [CGFloat] = [1, 4]
                path.setLineDash(pattern, count: 2, phase: 0)
            }
            path.stroke()
        }
    }
}
