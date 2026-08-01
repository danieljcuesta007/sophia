// StatusWindow — what you get when you click Sophia in the Dock. A menu-bar
// agent is invisible by design, so the Dock click opens this instead: current
// state, the keyboard map, and a scratch pad wired like any other text field —
// type in it and the ambient loop underlines it, cards and all. The fastest
// way to see Sophia work without leaving her.

import AppKit

final class StatusWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    /// Set by the app: reads and writes the "open at launch" preference.
    var showAtLaunch: () -> Bool = { true }
    var setShowAtLaunch: (Bool) -> Void = { _ in }

    /// The §7.1 regression sentence — seed text so the scratch pad shows
    /// underlines within a second of the window opening.
    private static let seedText =
        "Type here to try Sophia. Their going to the meeting tomorrow and i "
        + "think we should discuss weather we hired more people last quater."

    func show(status: String) {
        if let window {
            statusLabel?.stringValue = status
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = build(status: status)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 0),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = "Sophia Write"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = content
        w.setContentSize(content.fittingSize)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    func update(status: String) {
        statusLabel?.stringValue = status
    }

    private func build(status: String) -> NSView {
        let mark = NSImageView(image: Self.markImage(height: 34))
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 30).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let title = NSTextField(labelWithString: "Sophia Write")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let statusField = NSTextField(labelWithString: status)
        statusField.font = .systemFont(ofSize: 12)
        statusField.textColor = .secondaryLabelColor
        statusLabel = statusField

        let header = NSStackView(views: [mark, title])
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .centerY

        // Keyboard map (§16), the part worth memorizing.
        let keys: [(String, String)] = [
            ("\u{2318}\u{21E7}K", "Rewrite the selected text"),
            ("\u{2318}\u{21E7};", "Jump to next suggestion"),
            ("\u{2318}\u{21E7}'", "Accept the open card"),
            ("\u{2325}\u{21E7}D", "Add word to dictionary"),
            ("\u{2325}\u{21E7}P", "Pause or resume"),
            ("esc", "Dismiss the card"),
        ]
        let grid = NSGridView(views: keys.map { key, what in
            let k = NSTextField(labelWithString: key)
            k.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            let v = NSTextField(labelWithString: what)
            v.font = .systemFont(ofSize: 12)
            v.textColor = .secondaryLabelColor
            return [k, v]
        })
        grid.columnSpacing = 16
        grid.rowSpacing = 5

        let tryLabel = NSTextField(labelWithString: "TRY IT")
        tryLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        tryLabel.textColor = .tertiaryLabelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.separatorColor.cgColor
        let text = NSTextView()
        text.string = Self.seedText
        text.font = .systemFont(ofSize: 14)
        text.isRichText = false
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.autoresizingMask = [.width]
        scroll.documentView = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 120),
            scroll.widthAnchor.constraint(equalToConstant: 420),
        ])

        let launchToggle = NSButton(
            checkboxWithTitle: "Open this window at launch",
            target: self, action: #selector(launchToggled(_:)))
        launchToggle.state = showAtLaunch() ? .on : .off
        launchToggle.font = .systemFont(ofSize: 11)

        let stack = NSStackView(
            views: [header, statusField, grid, tryLabel, scroll, launchToggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(18, after: statusField)
        stack.setCustomSpacing(18, after: grid)
        stack.setCustomSpacing(6, after: tryLabel)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        return stack
    }

    @objc private func launchToggled(_ sender: NSButton) {
        setShowAtLaunch(sender.state == .on)
    }

    /// The brand mark drawn in code, in the brand green: stem, two branches
    /// leaving it on a vertical tangent, dot above.
    static func markImage(height: CGFloat) -> NSImage {
        let w = height * 0.88
        return NSImage(size: NSSize(width: w, height: height), flipped: false) { rect in
            OverlayController.styleColor.setStroke()
            OverlayController.styleColor.setFill()
            let midX = rect.width / 2
            let u = rect.height / 34.0  // design units

            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: midX, y: 3 * u))
            stem.line(to: NSPoint(x: midX, y: 25 * u))
            stem.lineWidth = 4.4 * u
            stem.lineCapStyle = .round
            stem.stroke()

            NSColor.labelColor.setStroke()
            for (rootY, dx, tipY) in [(9.0, 8.0, 18.0), (15.0, -8.0, 23.0)]
                as [(CGFloat, CGFloat, CGFloat)]
            {
                let branch = NSBezierPath()
                branch.move(to: NSPoint(x: midX, y: rootY * u))
                branch.curve(
                    to: NSPoint(x: midX + dx * u, y: tipY * u),
                    controlPoint1: NSPoint(x: midX, y: (rootY + 5) * u),
                    controlPoint2: NSPoint(x: midX + dx * 0.55 * u, y: (tipY - 1) * u))
                branch.lineWidth = 4.0 * u
                branch.lineCapStyle = .round
                branch.stroke()
            }

            OverlayController.styleColor.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: midX - 2.6 * u, y: 28.6 * u, width: 5.2 * u, height: 5.2 * u)).fill()
            return true
        }
    }
}
