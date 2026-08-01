// RewritePanel — the ⌘⇧K surface (blueprint §12.2). Non-activating: the
// target app keeps focus and its selection while the panel floats. Verb row +
// free-text instruction; result shown as an inline diff; nothing is applied
// until Accept (AC-16).

import AppKit

protocol RewritePanelDelegate: AnyObject {
    func rewritePanel(_ panel: RewritePanel, run mode: RewriteMode, custom: String?)
    func rewritePanelAccept(_ panel: RewritePanel)
    func rewritePanelClosed(_ panel: RewritePanel)
}

final class RewritePanel: NSObject, NSTextFieldDelegate {
    weak var delegate: RewritePanelDelegate?
    private var panel: NSPanel?
    private var statusLabel: NSTextField?
    private var diffLabel: NSTextField?
    private var acceptButton: NSButton?
    private var customField: NSTextField?

    private(set) var span = ""
    private(set) var result: String?

    var isOpen: Bool { panel?.isVisible == true }

    func open(span: String, near screenPoint: CGPoint) {
        close()
        self.span = span
        self.result = nil

        let content = build()
        let size = content.fittingSize
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        p.title = "Rewrite"
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = content

        let screen = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame ?? .zero
        var origin = CGPoint(x: screenPoint.x, y: screenPoint.y - size.height - 12)
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        p.setFrameOrigin(origin)
        p.orderFrontRegardless()
        panel = p
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        result = nil
    }

    // MARK: state transitions (driven by the app delegate)

    func showGenerating(_ mode: String) {
        statusLabel?.stringValue = "Rewriting (\(mode))\u{2026}"
        acceptButton?.isEnabled = false
        diffLabel?.attributedStringValue = NSAttributedString(string: "")
    }

    func showRejected(_ reason: String) {
        statusLabel?.stringValue = reason
        acceptButton?.isEnabled = false
        result = nil
    }

    func showDiff(original: String, final: String, hunks: [DiffHunk]) {
        result = final
        statusLabel?.stringValue = "Review, then Accept. Nothing changes until you do."
        diffLabel?.attributedStringValue = Self.diffText(original: original, hunks: hunks)
        acceptButton?.isEnabled = true
        resize()
    }

    private func resize() {
        guard let panel, let content = panel.contentView else { return }
        let size = content.fittingSize
        var frame = panel.frame
        let delta = size.height - frame.height
        frame.origin.y -= delta
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    // MARK: actions

    @objc private func verbTapped(_ sender: NSButton) {
        guard let mode = RewriteMode(rawValue: sender.title) else { return }
        delegate?.rewritePanel(self, run: mode, custom: nil)
    }

    @objc private func acceptTapped() {
        delegate?.rewritePanelAccept(self)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Return in the instruction field runs the custom rewrite.
        guard (obj.userInfo?["NSTextMovement"] as? Int) == NSReturnTextMovement,
              let text = customField?.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return }
        delegate?.rewritePanel(self, run: .professional, custom: text)
    }

    // MARK: layout

    private func build() -> NSView {
        let preview = NSTextField(labelWithString: Self.truncate(span, to: 140))
        preview.font = .systemFont(ofSize: 12)
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = 3
        preview.preferredMaxLayoutWidth = 360

        let verbs = NSStackView(views: RewriteMode.allCases.map { mode in
            let b = NSButton(
                title: mode.rawValue, target: self, action: #selector(verbTapped(_:)))
            b.bezelStyle = .rounded
            b.controlSize = .small
            return b
        })
        verbs.orientation = .horizontal
        verbs.spacing = 6

        let custom = NSTextField(string: "")
        custom.placeholderString = "Or tell Sophia what to do\u{2026} (return to run)"
        custom.font = .systemFont(ofSize: 12)
        custom.delegate = self
        custom.translatesAutoresizingMaskIntoConstraints = false
        custom.widthAnchor.constraint(equalToConstant: 372).isActive = true
        customField = custom

        let status = NSTextField(labelWithString: "Pick a rewrite, or type an instruction.")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .tertiaryLabelColor
        statusLabel = status

        let diff = NSTextField(labelWithString: "")
        diff.font = .systemFont(ofSize: 13)
        diff.maximumNumberOfLines = 10
        diff.preferredMaxLayoutWidth = 360
        diff.lineBreakMode = .byWordWrapping
        diffLabel = diff

        let accept = NSButton(title: "Accept", target: self, action: #selector(acceptTapped))
        accept.bezelStyle = .rounded
        accept.controlSize = .small
        accept.keyEquivalent = "\r"
        accept.bezelColor = OverlayController.styleColor
        accept.isEnabled = false
        acceptButton = accept

        let hint = NSTextField(labelWithString: "esc closes without applying")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        let buttonRow = NSStackView(views: [accept, hint])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [preview, verbs, custom, status, diff, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 14, right: 16)
        return stack
    }

    private static func truncate(_ s: String, to n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "\u{2026}"
    }

    /// Original with hunk befores struck in red and afters inserted in green.
    static func diffText(original: String, hunks: [DiffHunk]) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        let struck: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: OverlayController.correctionColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ]
        let inserted: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: OverlayController.styleColor,
        ]
        let out = NSMutableAttributedString()
        let units = Array(original.utf16)
        var cursor = 0
        for h in hunks.sorted(by: { $0.start < $1.start }) {
            guard h.start >= cursor, h.end <= units.count else { continue }
            if h.start > cursor {
                out.append(NSAttributedString(
                    string: String(
                        utf16CodeUnits: Array(units[cursor..<h.start]),
                        count: h.start - cursor),
                    attributes: base))
            }
            if !h.before.isEmpty {
                out.append(NSAttributedString(string: h.before, attributes: struck))
                out.append(NSAttributedString(string: " ", attributes: base))
            }
            out.append(NSAttributedString(string: h.after, attributes: inserted))
            cursor = h.end
        }
        if cursor < units.count {
            out.append(NSAttributedString(
                string: String(
                    utf16CodeUnits: Array(units[cursor...]), count: units.count - cursor),
                attributes: base))
        }
        return out
    }
}
