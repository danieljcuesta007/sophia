// sophia-write — ambient writing layer for macOS, Phase 1 (ambient core).
// Menu-bar agent: watches the focused text field, lints with the Rust core
// (Harper + Sophia's linters), underlines via a click-through overlay, applies
// accepted fixes through Cadence's insertion engine.
//
// `sophia-write selftest` runs the headless invariants and exits — this
// machine has no XCTest (Command Line Tools only), Cadence's pattern.

import AppKit
import ApplicationServices
import ServiceManagement
import SophiaInsertion

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
    private let statusWindow = StatusWindow()
    private let rewritePanel = RewritePanel()
    /// Issues from the last completed lint — reused to reposition underlines
    /// on scroll without a re-lint.
    private var lastIssues: [Issue] = []
    private var lastReposition = Date.distantPast
    private var metricsTimer: Timer?

    private var statusItem: NSStatusItem?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    private var localClickMonitor: Any?
    private var localScrollMonitor: Any?
    /// Belt-and-braces sweep: if focus moved without a notification we caught,
    /// stale marks get at most this long to live.
    private var validityTimer: Timer?
    private var trustPoll: Timer?
    private var wasTrusted = false
    /// The surface the current marks belong to; accepts must use the same one.
    private var activeSurface: TextSurface?
    /// Sentence clusters for the current marks (drives the sentence-diff card).
    private var sentenceGroups: [SentenceGroup] = []
    /// Dismissals stick for the session (dogfood: re-flagging a dismissed issue
    /// on every settle reads as nagging). Keyed per app + issue identity, not
    /// position, so it survives the text shifting around it.
    private var dismissed: Set<String> = []

    private func dismissKey(_ issue: Issue) -> String {
        "\(watcher.frontBundleID ?? "")|\(issue.anchor_text)|\(issue.kind)|\(issue.replacement ?? "")"
    }
    private var lastFocusDescription = "No text field focused"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()

        // Honest, once: the agent is useless without Accessibility.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        wasTrusted = AXIsProcessTrustedWithOptions(options)

        watcher.delegate = self
        card.delegate = self
        rewritePanel.delegate = self
        wireHotkeys()

        // AC-15: pre-warm the model at launch, off the main thread — the user
        // never meets the 3.47 s cold path.
        if #available(macOS 26.0, *) {
            DispatchQueue.global(qos: .utility).async {
                RewriteEngine.shared.prewarm()
            }
        }
        startMetrics()

        if wasTrusted {
            startWatching()
        }
        // AC-12: revocation at runtime tears everything down; a later grant
        // starts the agent without a relaunch.
        trustPoll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.pollTrust()
        }
        statusWindow.showAtLaunch = { [weak self] in
            self?.settings.showWindowAtLaunch ?? true
        }
        statusWindow.setShowAtLaunch = { [weak self] value in
            self?.settings.setShowWindowAtLaunch(value)
        }
        // The Dock click opens the window, so a launch from the Dock should
        // feel the same — but anyone running Sophia at login can turn this off
        // in the window itself rather than meeting it every morning.
        if settings.showWindowAtLaunch {
            statusWindow.show(status: currentStatusLine())
        }
        dlog("launched; trusted=\(wasTrusted)")
    }

    /// Clicking the Dock icon while running (LSUIElement apps get this when
    /// re-opened from Finder/Dock): show the window.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        statusWindow.show(status: currentStatusLine())
        return true
    }

    private func currentStatusLine() -> String {
        if !wasTrusted {
            return "Needs Accessibility permission — grant it in Privacy & Security."
        }
        if settings.paused { return "Paused. \u{2325}\u{21E7}P resumes." }
        return "Watching. Focus any text field, pause typing, and suggestions underline."
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
            rewritePanel.close()
            // Tear the observers down too: without Accessibility there is
            // nothing for them to observe, and startWatching() re-creates them
            // if permission comes back (AC-12).
            for monitor in [clickMonitor, scrollMonitor, localClickMonitor,
                            localScrollMonitor].compactMap({ $0 }) {
                NSEvent.removeMonitor(monitor)
            }
            clickMonitor = nil
            scrollMonitor = nil
            localClickMonitor = nil
            localScrollMonitor = nil
            validityTimer?.invalidate()
            validityTimer = nil
            activeSurface = nil
            lastIssues = []
            lastFocusDescription = "Accessibility permission needed"
        }
        refreshStatusIcon()
        dlog("trust changed: \(trusted)")
    }

    private func startWatching() {
        watcher.start()
        _ = hotkeys.start()
        // AC-27 keeps the overlay click-through, so clicks are observed — never
        // intercepted. Clicking an underline both places the caret (the app
        // gets the click) and opens the card.
        //
        // GLOBAL monitors only see events delivered to OTHER apps, so each
        // needs a LOCAL twin or Sophia's own scratch pad — the surface the
        // Dock window exists to demo — would be inert.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) {
                [weak self] _ in
                self?.handleGlobalClick()
            }
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) {
                [weak self] event in
                // ONLY the scratch pad. Without this guard a click on the
                // card's own Accept button hit-tests as "clicked away from an
                // underline", closing the card before the button ever fires.
                guard let self, self.statusWindow.owns(event.window) else { return event }
                DispatchQueue.main.async { self.handleGlobalClick() }
                return event
            }
        }
        if scrollMonitor == nil {
            // AX has no scroll notification. Grammarly-level fluency means the
            // marks RIDE the scroll, not blink out: recompute bounds from the
            // last lint (a few ms) instead of hiding and re-linting. The card
            // closes — its anchor moved.
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) {
                [weak self] _ in
                self?.repositionAfterScroll()
            }
            localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) {
                [weak self] event in
                self?.repositionAfterScroll()
                return event
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
        hotkeys.cardIsOpen = { [weak self] in
            self?.card.isOpen == true || self?.rewritePanel.isOpen == true
        }
        hotkeys.hasMarks = { [weak self] in self?.overlay.marks.isEmpty == false }
        hotkeys.hasSurface = { [weak self] in self?.activeSurface != nil }
        hotkeys.onEscape = { [weak self] in
            guard let self else { return }
            if self.rewritePanel.isOpen {
                self.rewritePanel.close()
            } else {
                self.card.close()
            }
        }
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
        hotkeys.onRewrite = { [weak self] in self?.openRewrite() }
        hotkeys.rewriteEnabled = { [weak self] in
            guard let self, !self.settings.paused, self.wasTrusted else { return false }
            guard #available(macOS 26.0, *) else { return false }
            // §16 conflict policy: never steal ⌘⇧K in an app turned off.
            return self.settings.mode(for: self.watcher.frontBundleID) != .off
        }
    }

    // MARK: rewrite (⌘⇧K)

    private func openRewrite() {
        guard #available(macOS 26.0, *), RewriteEngine.shared.isAvailable else {
            TransientNotice.show(
                "Rewrite needs Apple Intelligence enabled on this Mac",
                nearAXRect: mouseAXRect())
            return
        }
        let report = readFocused()
        guard let selection = report.selectedText,
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            TransientNotice.show(
                "Select some text, then press \u{2318}\u{21E7}K",
                nearAXRect: mouseAXRect())
            return
        }
        rewritePanel.open(span: selection, near: NSEvent.mouseLocation)
    }

    /// A small AX-coordinate rect at the mouse for anchoring notices.
    private func mouseAXRect() -> CGRect {
        let cocoa = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: cocoa.x, y: screenHeight - cocoa.y, width: 1, height: 20)
    }

    // MARK: scroll fluency

    private func repositionAfterScroll() {
        guard !overlay.marks.isEmpty || card.isOpen else { return }
        card.close()  // its anchor moved; reopening is one click away
        guard let surface = activeSurface, !lastIssues.isEmpty else {
            overlay.hide()
            return
        }
        // Throttle: scroll events arrive in bursts; bounds are 0-5 ms each,
        // but there is no reason to recompute more than ~12x/second.
        guard Date().timeIntervalSince(lastReposition) > 0.08 else { return }
        lastReposition = Date()
        guard watcher.surfaceStillFocused() else {
            watcherDidInvalidate()
            return
        }
        let marks: [UnderlineMark] = lastIssues.compactMap { issue in
            guard !dismissed.contains(dismissKey(issue)) else { return nil }
            let rects = surface.bounds(for: issue.utf16Range)
            guard !rects.isEmpty else { return nil }
            return UnderlineMark(issue: issue, rects: rects)
        }
        overlay.show(marks: marks, clippedTo: surface.visibleFrame())
    }

    // MARK: soak metrics (AC-11 evidence)

    private func startMetrics() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            let mb = Self.residentMB()
            let line = "\(ISO8601DateFormatter().string(from: Date())) rss=\(mb)MB\n"
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/SophiaWrite", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("metrics.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    private static func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.resident_size / 1_048_576)
    }

    private func togglePause() {
        settings.setPaused(!settings.paused)
        overlay.hide()
        card.close()
        watcher.refocus()  // AC-10: immediate
        refreshStatusIcon()
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
        if #available(macOS 26.0, *) {
            card.explainEnabled = RewriteEngine.shared.isAvailable
        } else {
            card.explainEnabled = false
        }
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
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatusIcon()
    }

    /// The brand mark, drawn in code (no bundled assets to lose): the Didot S
    /// as a template image. States read at a glance — dimmed when paused, a
    /// warning triangle when the agent has no Accessibility permission.
    fileprivate func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        if !wasTrusted {
            let warn = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Sophia Write needs Accessibility permission")
            warn?.isTemplate = true
            button.image = warn
            button.alphaValue = 1
            return
        }
        button.image = Self.menuBarGlyph
        button.alphaValue = settings.paused ? 0.4 : 1.0
    }

    /// The brand S at menu-bar scale, as a template image so macOS tints it
    /// for light and dark menu bars.
    private static let menuBarGlyph: NSImage = BrandMark.image(
        height: 17, color: .black, template: true)


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
                guard !self.dismissed.contains(self.dismissKey(issue)) else { return nil }
                let rects = surface.bounds(for: issue.utf16Range)
                guard !rects.isEmpty else { return nil }
                return UnderlineMark(issue: issue, rects: rects)
            }
            self.lastIssues = issues
            self.sentenceGroups = SentenceGrouper.groups(
                text: text, issues: marks.map(\.issue))
            self.overlay.show(marks: marks, clippedTo: surface.visibleFrame())
            self.refreshStatusIcon()
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
        lastIssues = []
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
        let anchor = overlay.marks.first { $0.issue == issue }?.rects.first
        let outcome = Acceptor.accept(issue: issue, surface: surface)
        card.close()
        handle(outcome, replacementText: issue.replacement, anchor: anchor)
        watcher.refocus()
    }

    /// Shared accept aftermath. Selection failure means this field can't be
    /// edited in place (WebKit today) — park the fix on the clipboard and say
    /// so; the words are one ⌘V away, never lost. Text-moved stays silent by
    /// contract (the user is typing; the underline will re-settle).
    private func handle(_ outcome: AcceptOutcome, replacementText: String?,
                        anchor: CGRect?) {
        switch outcome {
        case .applied(let result):
            dlog("applied via \(result.strategy.rawValue), verify=\(result.verification.rawValue)")
        case .abandonedSelectionFailed:
            if let replacementText, let anchor {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(replacementText, forType: .string)
                TransientNotice.show(
                    "Can't edit here in place — fix copied, paste with \u{2318}V",
                    nearAXRect: anchor)
            }
            dlog("accept abandoned: selection failed")
        case .abandonedTextMoved, .abandonedNoReplacement:
            dlog("accept abandoned: \(outcome)")
        }
    }

    func cardAcceptedGroup(_ group: SentenceGroup) {
        guard let surface = activeSurface else {
            card.close()
            return
        }
        let anchor = overlay.marks
            .first { group.issues.contains($0.issue) }?.rects.first
        let outcome = Acceptor.accept(group: group, surface: surface)
        card.close()
        handle(outcome, replacementText: SentenceGrouper.corrected(group),
               anchor: anchor)
        watcher.refocus()
    }

    func cardDismissed(_ issue: Issue) {
        dismissed.insert(dismissKey(issue))
        card.close()
        watcher.refocus()  // the underline disappears now, not on the next edit
    }

    func cardDismissedGroup(_ group: SentenceGroup) {
        for issue in group.issues {
            dismissed.insert(dismissKey(issue))
        }
        card.close()
        watcher.refocus()
    }

    func cardWantsExplanation(_ issue: Issue) {
        guard #available(macOS 26.0, *), let replacement = issue.replacement else {
            card.updateMessage(issue.message)
            return
        }
        Task { @MainActor in
            do {
                let why = try await RewriteEngine.shared.explain(
                    anchor: issue.anchor_text, replacement: replacement,
                    message: issue.message)
                // Only speak if the card still shows this issue.
                if self.card.issue == issue {
                    self.card.updateMessage(why)
                }
            } catch {
                if self.card.issue == issue {
                    self.card.updateMessage(issue.message)
                }
            }
        }
    }

    func cardAddedToDictionary(_ issue: Issue) {
        dictionary.add(issue.anchor_text.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted))
        card.close()
        watcher.refocus()  // AC-9: the flag disappears on the next pass
    }
}

// MARK: - RewritePanelDelegate

extension AppDelegate: RewritePanelDelegate {
    func rewritePanel(_ panel: RewritePanel, run mode: RewriteMode, custom: String?) {
        guard #available(macOS 26.0, *) else { return }
        let span = panel.span
        panel.showGenerating(custom ?? mode.rawValue)
        Task { @MainActor in
            do {
                let raw = try await RewriteEngine.shared.rewrite(
                    span, mode: mode, custom: custom)
                // The guards own the verdict; a custom instruction gets the
                // loosest bounds (professional's).
                switch RewriteGuards.inspect(
                    original: span, rewritten: raw, mode: custom == nil ? mode : .professional)
                {
                case .ok(let final, let hunks):
                    panel.showDiff(original: span, final: final, hunks: hunks)
                case .rejected(let reason):
                    panel.showRejected(reason)
                }
            } catch {
                panel.showRejected("The model could not respond. Try again.")
                dlog("rewrite failed: \(error)")
            }
        }
    }

    func rewritePanelAccept(_ panel: RewritePanel) {
        guard let final = panel.result else { return }
        // Re-verify the selection is still exactly the span we rewrote — if
        // the user touched it while reviewing, abandon (AC-7's principle).
        let report = readFocused()
        guard report.selectedText == panel.span else {
            panel.showRejected("The selection changed — nothing applied.")
            return
        }
        panel.close()
        let result = InsertionEngine().insert(final)
        if !result.inserted {
            TransientNotice.show(
                "Couldn't apply here — rewrite is on the clipboard (\u{2318}V)",
                nearAXRect: mouseAXRect())
        }
        dlog("rewrite applied via \(result.strategy.rawValue), verify=\(result.verification.rawValue)")
        watcher.refocus()
    }

    func rewritePanelClosed(_ panel: RewritePanel) {}
}

// MARK: - menu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var statusLine = wasTrusted ? lastFocusDescription : "Accessibility permission needed"
        let issueCount = overlay.marks.count
        if wasTrusted, !settings.paused, issueCount > 0 {
            statusLine += " — \(issueCount) suggestion\(issueCount == 1 ? "" : "s")"
        }
        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !wasTrusted {
            menu.addItem(NSMenuItem(
                title: "Open Privacy & Security Settings",
                action: #selector(openAXSettings), keyEquivalent: ""))
        }
        menu.addItem(.separator())

        // Key equivalents shown here are hints; the chords are global taps.
        let pause = NSMenuItem(
            title: settings.paused ? "Resume Checking" : "Pause Checking",
            action: #selector(menuTogglePause), keyEquivalent: "p")
        pause.keyEquivalentModifierMask = [.option, .shift]
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
            title: "Open Sophia Window", action: #selector(openWindow),
            keyEquivalent: ""))
        menu.addItem(NSMenuItem(
            title: "Open Dictionary File", action: #selector(openDictionary),
            keyEquivalent: ""))

        // Launch at Login only works from the packaged .app bundle.
        if Bundle.main.bundleURL.pathExtension == "app" {
            let login = NSMenuItem(
                title: "Launch at Login", action: #selector(toggleLaunchAtLogin),
                keyEquivalent: "")
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }

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

    @objc private func openWindow() {
        statusWindow.show(status: currentStatusLine())
    }

    @objc private func openDictionary() {
        ConfigPaths.ensureDir()
        if !FileManager.default.fileExists(atPath: ConfigPaths.dictionaryFile.path) {
            dictionary.add("Addisuna")  // seed with the canonical example
        }
        NSWorkspace.shared.open(ConfigPaths.dictionaryFile)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            dlog("launch-at-login toggle failed: \(error)")
        }
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
