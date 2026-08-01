// ComboHotkeys — global chord hotkeys via a CGEvent tap, following Cadence's
// HotkeyMonitor tap discipline: re-enable when macOS disables the tap for
// latency, consume only chords that are ours, pass everything else untouched.
//
// Phase-1 map (blueprint §16): ⌘⇧; jump to next issue · ⌘⇧' accept focused
// suggestion · ⌥⇧D add word under caret to dictionary · ⌥⇧P pause/resume ·
// Escape peels the open card (consumed only while a card is open).

import AppKit
import CoreGraphics

final class ComboHotkeys {
    var onNextIssue: (() -> Void)?
    var onAccept: (() -> Void)?
    var onAddToDictionary: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onEscape: (() -> Void)?
    var onRewrite: (() -> Void)?
    /// Whether ⌘⇧K is Sophia's in the frontmost app (not paused, app not off,
    /// rewrite engine present). Read on the tap thread — must be cheap.
    var rewriteEnabled: () -> Bool = { false }
    /// Governs Escape consumption; read on the tap thread (main run loop).
    var cardIsOpen: () -> Bool = { false }
    /// Conflict policy (blueprint §16): a chord is consumed only when Sophia has
    /// something to do with it — otherwise it passes through to the app that
    /// owns it (⌘⇧K-style IDE collisions).
    var hasMarks: () -> Bool = { false }
    var hasSurface: () -> Bool = { false }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static let kK: Int64 = 40
    private static let kSemicolon: Int64 = 41
    private static let kQuote: Int64 = 39
    private static let kD: Int64 = 2
    private static let kP: Int64 = 35
    private static let kEscape: Int64 = 53

    /// Returns false when the tap can't be created (Accessibility not granted).
    func start() -> Bool {
        let mask = 1 << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<ComboHotkeys>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let cmdShift = flags.contains(.maskCommand) && flags.contains(.maskShift)
            && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
        let optShift = flags.contains(.maskAlternate) && flags.contains(.maskShift)
            && !flags.contains(.maskCommand) && !flags.contains(.maskControl)

        if cmdShift, keyCode == Self.kK, rewriteEnabled() {
            DispatchQueue.main.async { self.onRewrite?() }
            return nil
        }
        if cmdShift, keyCode == Self.kSemicolon, hasMarks() {
            DispatchQueue.main.async { self.onNextIssue?() }
            return nil
        }
        if cmdShift, keyCode == Self.kQuote, cardIsOpen() {
            DispatchQueue.main.async { self.onAccept?() }
            return nil
        }
        if optShift, keyCode == Self.kD, hasSurface() {
            DispatchQueue.main.async { self.onAddToDictionary?() }
            return nil
        }
        if optShift, keyCode == Self.kP {
            DispatchQueue.main.async { self.onTogglePause?() }
            return nil
        }
        if keyCode == Self.kEscape, flags.intersection([
            .maskCommand, .maskShift, .maskAlternate, .maskControl,
        ]).isEmpty, cardIsOpen() {
            DispatchQueue.main.async { self.onEscape?() }
            return nil  // consumed: Esc must not also close the user's dialog
        }
        return Unmanaged.passUnretained(event)
    }
}
