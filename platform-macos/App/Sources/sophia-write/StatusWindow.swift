// StatusWindow — what you get when you click Sophia in the Dock. A menu-bar
// agent is invisible by design, so the Dock click opens this instead: current
// state, the keyboard map, and a scratch pad wired like any other text field —
// type in it and the ambient loop underlines it, cards and all. The fastest
// way to see Sophia work without leaving her.

import AppKit

final class StatusWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var statusLabel: NSTextField?

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
        let leaf = NSImageView(
            image: NSImage(systemSymbolName: "leaf", accessibilityDescription: nil)
                ?? NSImage())
        leaf.symbolConfiguration = .init(pointSize: 30, weight: .medium)
        leaf.contentTintColor = OverlayController.styleColor

        let title = NSTextField(labelWithString: "Sophia Write")
        title.font = NSFont(name: "Didot-Bold", size: 24)
            ?? .systemFont(ofSize: 24, weight: .bold)

        let statusField = NSTextField(labelWithString: status)
        statusField.font = .systemFont(ofSize: 12)
        statusField.textColor = .secondaryLabelColor
        statusLabel = statusField

        let header = NSStackView(views: [leaf, title])
        header.orientation = .horizontal
        header.spacing = 10

        // Keyboard map (§16), the part worth memorizing.
        let keys: [(String, String)] = [
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

        let stack = NSStackView(views: [header, statusField, grid, tryLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(18, after: statusField)
        stack.setCustomSpacing(18, after: grid)
        stack.setCustomSpacing(6, after: tryLabel)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        return stack
    }
}
