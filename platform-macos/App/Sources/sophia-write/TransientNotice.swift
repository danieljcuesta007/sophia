// TransientNotice — a small honest status line that appears near the point of
// action and removes itself. Used when an edit could not be applied in place
// and the text was parked on the clipboard instead (blueprint §29: text is
// never lost). No animation, no sound (§12.4); it simply is, then isn't.

import AppKit

enum TransientNotice {
    private static var panel: NSPanel?

    static func show(_ message: String, nearAXRect anchor: CGRect) {
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor

        let box = NSVisualEffectView()
        box.material = .popover
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
        ])

        let size = box.fittingSize
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = box

        let cocoaAnchor = OverlayController.cocoaRect(fromAX: anchor)
        let screen = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame ?? .zero
        var origin = CGPoint(x: cocoaAnchor.minX, y: cocoaAnchor.minY - size.height - 8)
        if origin.y < screen.minY { origin.y = cocoaAnchor.maxY + 8 }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        p.setFrameOrigin(origin)
        p.orderFrontRegardless()
        panel = p

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak p] in
            p?.orderOut(nil)
            if panel === p { panel = nil }
        }
    }
}
