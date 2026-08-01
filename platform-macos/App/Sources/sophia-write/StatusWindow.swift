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

    /// Is this the Sophia window? Underline hit-testing inside our own process
    /// must apply here (the scratch pad) and nowhere else — a click on the
    /// suggestion card's own buttons must not be treated as a click on the
    /// document beneath it.
    func owns(_ candidate: NSWindow?) -> Bool {
        candidate != nil && candidate === window
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

    static func markImage(height: CGFloat) -> NSImage {
        BrandMark.image(height: height, upper: .labelColor,
                        lower: OverlayController.styleColor, template: false)
    }
}

/// The Sophia mark drawn in code — the same geometry as `assets/mkicon.py`:
/// two bowls of an S, each a thick round-capped arc, trimmed back from the
/// waist so they never touch. No bundled asset to go missing, and it renders
/// crisply at every size from the menu bar up.
enum BrandMark {
    /// Design constants mirror mkicon.py (canvas 1024): radius 150, weight 76,
    /// 15 degrees trimmed at the waist, 26 degrees of open terminal.
    private static let trim: CGFloat = 15
    private static let terminal: CGFloat = 26

    /// `template` yields a monochrome mask (menu bar); otherwise the two bowls
    /// take `upper` and `lower`.
    static func image(height: CGFloat, upper: NSColor, lower: NSColor,
                      template: Bool) -> NSImage
    {
        // The S is 4r tall and 2r wide, plus the stroke on each axis.
        let weight = height * (76.0 / 676.0)   // 4*150 + 76 = 676 design-tall
        let r = (height - weight) / 4
        let width = 2 * r + weight
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let midX = rect.width / 2
            let midY = rect.height / 2

            // AppKit is y-up, the design is y-down: mirror the angles.
            let top = NSBezierPath()
            top.appendArc(withCenter: NSPoint(x: midX, y: midY + r), radius: r,
                          startAngle: terminal, endAngle: 270 - trim,
                          clockwise: false)
            let bottom = NSBezierPath()
            bottom.appendArc(withCenter: NSPoint(x: midX, y: midY - r), radius: r,
                             startAngle: 90 - trim, endAngle: 180 + terminal,
                             clockwise: true)
            for (path, color) in [(top, upper), (bottom, lower)] {
                path.lineWidth = weight
                path.lineCapStyle = .round
                (template ? NSColor.black : color).setStroke()
                path.stroke()
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Sophia Write"
        return image
    }
}
