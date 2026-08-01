// sophia-write — ambient writing layer for macOS, Phase 1 (ambient core).
// Menu-bar agent: watches the focused text field, lints with the Rust core
// (Harper + Sophia's linters), underlines via a click-through overlay, applies
// accepted fixes through Cadence's insertion engine.
//
// `sophia-write selftest` runs the headless invariants and exits — this
// machine has no XCTest (Command Line Tools only), Cadence's pattern.

import AppKit
import ApplicationServices

func dlog(_ message: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["SOPHIA_DEBUG"] != nil {
        FileHandle.standardError.write(Data("[sophia] \(message())\n".utf8))
    }
}

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("selftest") {
            exit(SelfTest.run())
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // LSUIElement in the packaged bundle
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let dictionary = DictionaryStore()
    private lazy var lint = LintService(dictionary: dictionary)
    private lazy var watcher = AXWatcher(settings: settings)
    private let overlay = OverlayController()
    private let card = SuggestionCard()
    private let hotkeys = ComboHotkeys()

    private var statusItem: NSStatusItem?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    /// Belt-and-braces sweep: if focus moved without a notification we caught,
    /// stale marks get at most this long to live.
    private var validityTimer: Timer?
    private var trustPoll: Timer?
    private var wasTrusted = false
    /// The surface the current marks belong to; accepts must use the same one.
    private var activeSurface: TextSurface?
    /// Sentence clusters for the current marks (drives the sentence-diff card).
    private var sentenceGroups: [SentenceGroup] = []
    private var lastFocusDescription = "No text field focused"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()

        // Honest, once: the agent is useless without Accessibility.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        wasTrusted = AXIsProcessTrustedWithOptions(options)

        watcher.delegate = self
        card.delegate = self
        wireHotkeys()

        if wasTrusted {
            startWatching()
        }
        // AC-12: revocation at runtime tears everything down; a later grant
        // starts the agent without a relaunch.
        trustPoll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.pollTrust()
        }
        dlog("launched; trusted=\(wasTrusted)")
    }

    private func pollTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != wasTrusted else { return }
        wasTrusted = trusted
        if trusted {
            startWatching()
        } else {
            watcher.stop()
            hotkeys.stop()
            overlay.hide()
            card.close()
            activeSurface = nil
            lastFocusDescription = "Accessibility permission needed"
        }
        dlog("trust changed: \(trusted)")
    }

    private func startWatching() {
        watcher.start()
        _ = hotkeys.start()
        if clickMonitor == nil {
            // AC-27 keeps the overlay click-through, so clicks are observed —
            // never intercepted — via a global monitor. Clicking an underline
            // both places the caret (the app gets the click) and opens the card.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) {
                [weak self] _ in
                self?.handleGlobalClick()
            }
        }
        if scrollMonitor == nil {
            // AX has no scroll notification, so any scroll anywhere makes every
            // mark position suspect: hide immediately, re-settle after the pause.
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) {
                [weak self] _ in
                guard let self, !self.overlay.marks.isEmpty || self.card.isOpen else { return }
                self.watcher.noteScrolled()
            }
        }
        if validityTimer == nil {
            validityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
                [weak self] _ in
                guard let self, !self.overlay.marks.isEmpty else { return }
                if !self.watcher.surfaceStillFocused() {
                    dlog("validity sweep: focus moved — tearing down marks")
                    self.watcherDidInvalidate()
                    self.watcher.refocus()
                }
            }
        }
    }

    // MARK: hotkeys

    private func wireHotkeys() {
        hotkeys.cardIsOpen = { [weak self] in self?.card.isOpen == true }
        hotkeys.hasMarks = { [weak self] in self?.overlay.marks.isEmpty == false }
        hotkeys.hasSurface = { [weak self] in self?.activeSurface != nil }
        hotkeys.onEscape = { [weak self] in self?.card.close() }
        hotkeys.onTogglePause = { [weak self] in self?.togglePause() }
        hotkeys.onNextIssue = { [weak self] in self?.jumpToNextIssue() }
        hotkeys.onAccept = { [weak self] in
            guard let self else { return }
            if let group = self.card.group {
                self.cardAcceptedGroup(group)
            } else if let issue = self.card.issue {
                self.cardAccepted(issue)
            }
        }
        hotkeys.onAddToDictionary = { [weak self] in self?.addWordNearCaret() }
    }

    private func togglePause() {
        settings.setPaused(!settings.paused)
        overlay.hide()
        card.close()
        watcher.refocus()  // AC-10: immediate
        dlog("paused=\(settings.paused)")
    }

    private func jumpToNextIssue() {
        let marks = overlay.marks
        guard !marks.isEmpty else { return }
        let current = card.issue
        let index: Int
        if let current, let at = marks.firstIndex(where: { $0.issue == current }) {
            index = (at + 1) % marks.count
        } else {
            index = 0
        }
        openCard(for: marks[index])
    }

    private func addWordNearCaret() {
        // With a card open, learn that card's word. Otherwise learn the word
        // at the caret from the active surface.
        if let issue = card.issue, issue.isDictionaryCandidate {
            cardAddedToDictionary(issue)
            return
        }
        guard let surface = activeSurface,
              let element = Optional(surface.element),
              let text = surface.readText()
        else { return }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID()
        else { return }
        var caret = CFRange()
        guard AXValueGetValue((ref as! AXValue), .cfRange, &caret) else { return }
        let ns = text as NSString
        guard caret.location <= ns.length else { return }
        let word = wordAround(ns, index: min(caret.location, max(ns.length - 1, 0)))
        guard !word.isEmpty else { return }
        dictionary.add(word)
        watcher.refocus()
        dlog("dictionary add via hotkey: \(word)")
    }

    private func wordAround(_ text: NSString, index: Int) -> String {
        let alnum = CharacterSet.alphanumerics
        func isWordChar(_ i: Int) -> Bool {
            guard i >= 0, i < text.length else { return false }
            guard let scalar = Unicode.Scalar(text.character(at: i)) else { return false }
            return alnum.contains(scalar) || scalar == "'" || scalar == "-"
        }
        var start = index
        while isWordChar(start - 1) { start -= 1 }
        var end = index
        while isWordChar(end) { end += 1 }
        guard end > start else { return "" }
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    // MARK: clicks

    private func handleGlobalClick() {
        guard !overlay.marks.isEmpty else { return }
        // NSEvent.mouseLocation is Cocoa (bottom-left origin); marks are AX
        // (top-left). Convert and hit-test.
        let cocoa = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = CGPoint(x: cocoa.x, y: screenHeight - cocoa.y)
        guard let mark = overlay.mark(atAXPoint: axPoint) else {
            card.close()
            return
        }
        // The click also moves the caret in the target app; open after it lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.openCard(for: mark)
        }
    }

    private func openCard(for mark: UnderlineMark) {
        guard let rect = mark.rects.first else { return }
        // A sentence with several fixable issues gets the diff card with one
        // Fix Sentence action; a lone issue keeps the small card.
        if let group = sentenceGroups.first(where: { $0.issues.contains(mark.issue) }),
           group.fixableCount > 1 {
            card.show(group: group, nearAXRect: rect)
        } else {
            card.show(issue: mark.issue, nearAXRect: rect)
        }
    }

    // MARK: status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "text.badge.checkmark",
                accessibilityDescription: "Sophia Write")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: lint pipeline

    fileprivate func runLint(text: String, surface: TextSurface) {
        let started = Date()
        lint.lint(text) { [weak self] issues in
            guard let self, self.activeSurface === surface else { return }
            // Draw-time guard: if focus moved while we were linting, these
            // positions belong to a field that is no longer on screen.
            guard self.watcher.surfaceStillFocused() else {
                dlog("lint result dropped: focus moved before draw")
                return
            }
            let marks: [UnderlineMark] = issues.compactMap { issue in
                let rects = surface.bounds(for: issue.utf16Range)
                guard !rects.isEmpty else { return nil }
                return UnderlineMark(issue: issue, rects: rects)
            }
            self.sentenceGroups = SentenceGrouper.groups(
                text: text, issues: marks.map(\.issue))
            self.overlay.show(marks: marks, clippedTo: surface.visibleFrame())
            dlog(
                "marked \(marks.count)/\(issues.count) issues in "
                + "\(Int(Date().timeIntervalSince(started) * 1000)) ms")
        }
    }
}

// MARK: - AXWatcherDelegate

extension AppDelegate: AXWatcherDelegate {
    func watcherDidInvalidate() {
        lint.cancelPending()
        sentenceGroups = []
        overlay.hide()
        card.close()  // typing while a card is open abandons the edit (AC-7)
    }

    func watcher(_ watcher: AXWatcher, settledText: String, surface: TextSurface) {
        activeSurface = surface
        runLint(text: settledText, surface: surface)
    }

    func watcher(_ watcher: AXWatcher, focusChanged bundleID: String?, lintable: Bool) {
        if !lintable {
            activeSurface = nil
        }
        let app = bundleID ?? "unknown"
        if settings.paused {
            lastFocusDescription = "Paused"
        } else if settings.isDenied(bundleID) {
            lastFocusDescription = "Off in \(app) (deny list)"
        } else if lintable {
            lastFocusDescription = "Watching \(app)"
        } else {
            lastFocusDescription = "No text field in \(app)"
        }
    }
}

// MARK: - SuggestionCardDelegate

extension AppDelegate: SuggestionCardDelegate {
    func cardAccepted(_ issue: Issue) {
        guard let surface = activeSurface else {
            card.close()
            return
        }
        let outcome = Acceptor.accept(issue: issue, surface: surface)
        card.close()
        switch outcome {
        case .applied(let result):
            dlog("applied via \(result.strategy.rawValue), verify=\(result.verification.rawValue)")
        case .abandonedTextMoved, .abandonedSelectionFailed, .abandonedNoReplacement:
            // Every ambiguity resolves to doing nothing; the underline stays.
            dlog("accept abandoned: \(outcome)")
        }
        watcher.refocus()
    }

    func cardAcceptedGroup(_ group: SentenceGroup) {
        guard let surface = activeSurface else {
            card.close()
            return
        }
        let outcome = Acceptor.accept(group: group, surface: surface)
        card.close()
        switch outcome {
        case .applied(let result):
            dlog("sentence fixed via \(result.strategy.rawValue), verify=\(result.verification.rawValue)")
        case .abandonedTextMoved, .abandonedSelectionFailed, .abandonedNoReplacement:
            dlog("sentence fix abandoned: \(outcome)")
        }
        watcher.refocus()
    }

    func cardDismissed(_ issue: Issue) {
        card.close()
    }

    func cardAddedToDictionary(_ issue: Issue) {
        dictionary.add(issue.anchor_text.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted))
        card.close()
        watcher.refocus()  // AC-9: the flag disappears on the next pass
    }
}

// MARK: - menu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(
            title: wasTrusted ? lastFocusDescription : "Accessibility permission needed",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !wasTrusted {
            menu.addItem(NSMenuItem(
                title: "Open Privacy & Security Settings",
                action: #selector(openAXSettings), keyEquivalent: ""))
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: settings.paused ? "Resume Checking" : "Pause Checking",
            action: #selector(menuTogglePause), keyEquivalent: "")
        menu.addItem(pause)

        if let bundleID = watcher.frontBundleID, !settings.isDenied(bundleID) {
            let mode = settings.mode(for: bundleID)
            let sub = NSMenu()
            for (title, value) in [
                ("Full (underlines and fixes)", SettingsStore.Mode.full),
                ("Rewrite only", .rewriteOnly),
                ("Off", .off),
            ] {
                let item = NSMenuItem(
                    title: title, action: #selector(setAppMode(_:)), keyEquivalent: "")
                item.representedObject = value.rawValue
                item.state = mode == value ? .on : .off
                sub.addItem(item)
            }
            let holder = NSMenuItem(
                title: "In \(watcher.frontBundleID ?? "this app")",
                action: nil, keyEquivalent: "")
            menu.addItem(holder)
            menu.setSubmenu(sub, for: holder)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Open Dictionary File", action: #selector(openDictionary),
            keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Sophia Write", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    @objc private func menuTogglePause() { togglePause() }

    @objc private func setAppMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SettingsStore.Mode(rawValue: raw),
              let bundleID = watcher.frontBundleID
        else { return }
        settings.setMode(mode, for: bundleID)
        overlay.hide()
        card.close()
        watcher.refocus()
    }

    @objc private func openDictionary() {
        ConfigPaths.ensureDir()
        if !FileManager.default.fileExists(atPath: ConfigPaths.dictionaryFile.path) {
            dictionary.add("Addisuna")  // seed with the canonical example
        }
        NSWorkspace.shared.open(ConfigPaths.dictionaryFile)
    }

    @objc private func openAXSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
