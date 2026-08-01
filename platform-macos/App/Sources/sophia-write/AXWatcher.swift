// AXWatcher — the ambient loop's eyes (blueprint §12.1 state machine).
//
//   IDLE → WATCHING (focus enters lintable text) → TYPING (all UI suppressed)
//   → 300 ms idle → CHECKING (Harper, worker queue) → MARKED / WATCHING
//   any → focus leaves / app denied / secure field → IDLE (all UI torn down)
//
// Never freezes the target app: every AX element is messaging-timeout-bounded
// (AX.bound) and observer callbacks only snapshot + enqueue.

import AppKit
import ApplicationServices

protocol AXWatcherDelegate: AnyObject {
    /// Entered TYPING or IDLE — hide every piece of UI now (AC-5).
    func watcherDidInvalidate()
    /// A settled snapshot is ready to lint.
    func watcher(_ watcher: AXWatcher, settledText: String, surface: TextSurface)
    /// Focus context for the menu-bar status line.
    func watcher(_ watcher: AXWatcher, focusChanged bundleID: String?, lintable: Bool)
}

final class AXWatcher {
    weak var delegate: AXWatcherDelegate?
    private let settings: SettingsStore

    private(set) var surface: TextSurface?
    private(set) var frontBundleID: String?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var observedElement: AXUIElement?
    private var debounce: DispatchWorkItem?
    /// 300 ms idle before CHECKING (§12.1); AC-4 wants marks within 150 ms after.
    private let settleDelay: TimeInterval = 0.3

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        refocus()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        tearDownObserver()
        toIdle()
    }

    /// Re-resolve the focused element — called on app switch, permission
    /// changes, and pause toggles.
    func refocus() {
        frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        debounce?.cancel()

        guard !settings.paused,
              settings.mode(for: frontBundleID) == .full,
              AXIsProcessTrusted(),
              let element = AX.focusedElement()
        else {
            toIdle()
            delegate?.watcher(self, focusChanged: frontBundleID, lintable: false)
            return
        }

        // AC-8: secure fields get nothing — no observer, no surface, no UI.
        // Search boxes get nothing either: half-typed queries are not prose,
        // and marks over a browser page read as noise (dogfood 8/01).
        let subrole = AX.string(element, kAXSubroleAttribute)
        if subrole == "AXSecureTextField" || subrole == "AXSearchField" {
            toIdle()
            delegate?.watcher(self, focusChanged: frontBundleID, lintable: false)
            return
        }

        guard let surface = SurfaceFactory.make(for: element) else {
            toIdle()
            delegate?.watcher(self, focusChanged: frontBundleID, lintable: false)
            return
        }

        self.surface = surface
        observe(element: element)
        delegate?.watcher(self, focusChanged: frontBundleID, lintable: true)
        scheduleSettle()  // existing text deserves a pass too
    }

    private func toIdle() {
        surface = nil
        observedElement = nil
        debounce?.cancel()
        delegate?.watcherDidInvalidate()
    }

    // MARK: notifications

    @objc private func appActivated(_ note: Notification) {
        // Hide everything NOW — stale underlines painted over the new app are
        // worse than a briefly missing mark — then re-resolve once focus settles.
        delegate?.watcherDidInvalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refocus()
        }
    }

    /// The user scrolled somewhere. AX sends no scroll notification, so every
    /// mark position is now suspect: hide, then re-settle.
    func noteScrolled() {
        guard surface != nil else { return }
        delegate?.watcherDidInvalidate()
        scheduleSettle()
    }

    /// True when the system-focused element is still the one our surface wraps.
    /// Guards against missed focus notifications before anything is drawn.
    func surfaceStillFocused() -> Bool {
        guard let surface else { return false }
        guard let focused = AX.focusedElement() else { return false }
        if CFEqual(focused, surface.element) { return true }
        // WebKit surfaces wrap an ancestor web area of the focused element;
        // same pid is the honest check we have there.
        return AX.pid(focused) != nil && AX.pid(focused) == AX.pid(surface.element)
            && surface is WebKitTextSurface
    }

    private func observe(element: AXUIElement) {
        guard let pid = AX.pid(element) else { return }
        if pid != observedPID || observer == nil {
            tearDownObserver()
            var obs: AXObserver?
            let callback: AXObserverCallback = { _, _, notification, refcon in
                guard let refcon else { return }
                let me = Unmanaged<AXWatcher>.fromOpaque(refcon).takeUnretainedValue()
                me.handleAX(notification as String)
            }
            guard AXObserverCreate(pid, callback, &obs) == .success, let obs
            else { return }
            observer = obs
            observedPID = pid
            CFRunLoopAddSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        guard let observer else { return }
        // Focus moves within the app, values change, elements die, windows move.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        AX.bound(appElement)
        for note in [
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
            kAXUIElementDestroyedNotification,
            kAXSelectedTextChangedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
        ] {
            AXObserverAddNotification(observer, appElement, note as CFString, refcon)
            AXObserverAddNotification(observer, element, note as CFString, refcon)
        }
        observedElement = element
    }

    private func tearDownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
    }

    private func handleAX(_ notification: String) {
        switch notification {
        case kAXFocusedUIElementChangedNotification, kAXUIElementDestroyedNotification:
            refocus()
        case kAXValueChangedNotification, kAXSelectedTextChangedNotification:
            // TYPING: suppress all UI immediately (AC-5), then re-settle.
            delegate?.watcherDidInvalidate()
            scheduleSettle()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            // Positions are stale; hide and re-mark after the move settles.
            delegate?.watcherDidInvalidate()
            scheduleSettle()
        default:
            break
        }
    }

    private func scheduleSettle() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let surface = self.surface else { return }
            guard let text = surface.readText(), !text.isEmpty else {
                self.delegate?.watcherDidInvalidate()
                return
            }
            self.delegate?.watcher(self, settledText: text, surface: surface)
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }
}
