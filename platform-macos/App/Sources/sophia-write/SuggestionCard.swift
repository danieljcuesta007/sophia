// SuggestionCard — the one piece of visible chrome in the ambient loop
// (blueprint §12.1 CARD_OPEN). A non-activating panel: focus never leaves the
// user's document. No emojis, SF Symbols only, message under 12 words (§19).
//
// Anti-patterns honoured (§12.4): no popup on hover, no sound, no badge
// counts, no modal, no animation.

import AppKit

protocol SuggestionCardDelegate: AnyObject {
    func cardAccepted(_ issue: Issue)
    func cardDismissed(_ issue: Issue)
    func cardAddedToDictionary(_ issue: Issue)
}

final class SuggestionCard {
    weak var delegate: SuggestionCardDelegate?
    private var panel: NSPanel?
    private(set) var issue: Issue?

    var isOpen: Bool { panel?.isVisible == true }

    func show(issue: Issue, nearAXRect anchor: CGRect) {
        close()
        self.issue = issue

        let content = buildContent(for: issue)
        let size = content.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = content

        // Below the underline; above it if there is no room.
        let cocoaAnchor = OverlayController.cocoaRect(fromAX: anchor)
        var origin = CGPoint(x: cocoaAnchor.minX, y: cocoaAnchor.minY - size.height - 8)
        if origin.y < (NSScreen.main?.visibleFrame.minY ?? 0) {
            origin.y = cocoaAnchor.maxY + 8
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        issue = nil
    }

    // MARK: actions

    @objc private func acceptTapped() {
        guard let issue else { return }
        delegate?.cardAccepted(issue)
    }

    @objc private func dismissTapped() {
        guard let issue else { return }
        delegate?.cardDismissed(issue)
    }

    @objc private func dictionaryTapped() {
        guard let issue else { return }
        delegate?.cardAddedToDictionary(issue)
    }

    // MARK: layout

    private func buildContent(for issue: Issue) -> NSView {
        let box = NSVisualEffectView()
        box.material = .popover
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor

        let message = NSTextField(labelWithString: issue.message)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 2
        message.preferredMaxLayoutWidth = 260

        let change = NSTextField(labelWithString: changeLine(for: issue))
        change.font = .systemFont(ofSize: 13, weight: .medium)
        change.maximumNumberOfLines = 2
        change.preferredMaxLayoutWidth = 260

        let accept = NSButton(
            title: issue.replacement != nil ? "Accept" : "OK",
            target: self, action: #selector(acceptTapped))
        accept.bezelStyle = .rounded
        accept.controlSize = .small
        accept.keyEquivalent = "\r"
        accept.bezelColor = OverlayController.styleColor
        accept.isEnabled = issue.replacement != nil

        let dismiss = NSButton(
            title: "Dismiss", target: self, action: #selector(dismissTapped))
        dismiss.bezelStyle = .rounded
        dismiss.controlSize = .small

        var buttons: [NSView] = [accept, dismiss]
        if issue.isDictionaryCandidate {
            let learn = NSButton(
                title: "Add to Dictionary", target: self, action: #selector(dictionaryTapped))
            learn.bezelStyle = .rounded
            learn.controlSize = .small
            buttons.append(learn)
        }

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [change, message, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }

    private func changeLine(for issue: Issue) -> String {
        if let replacement = issue.replacement {
            return "\(issue.anchor_text) \u{2192} \(replacement)"
        }
        return issue.anchor_text
    }
}
