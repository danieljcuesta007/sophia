// Local stores (blueprint §18): personal dictionary shared with Cadence, and
// settings (pause, per-app rules). All JSON, all inspectable, all portable —
// paths derive from the home directory, never a hardcoded user (AC-29).
//
// The dictionary is merge-written: re-read immediately before every write and
// union, so another writer (Cadence, an editor) is never clobbered. Writes are
// atomic (temp file + rename).

import Foundation

enum ConfigPaths {
    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sophia", isDirectory: true)
    }
    static var dictionaryFile: URL { configDir.appendingPathComponent("dictionary.json") }
    static var settingsFile: URL { configDir.appendingPathComponent("settings.json") }

    static func ensureDir() {
        try? FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true)
    }
}

/// Shared personal dictionary — schema kept deliberately small so Cadence can
/// adopt it: {"version":1,"terms":[{"term":"Addisuna"}]}. Neither product owns
/// the file; unknown keys are preserved on write.
final class DictionaryStore {
    private(set) var terms: [String] = []
    private var raw: [String: Any] = ["version": 1]
    var onChange: (() -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1

    init() {
        load()
        watch()
    }

    func load() {
        guard let data = try? Data(contentsOf: ConfigPaths.dictionaryFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        raw = obj
        let entries = obj["terms"] as? [[String: Any]] ?? []
        terms = entries.compactMap { $0["term"] as? String }
    }

    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        load()  // merge-write: pick up concurrent edits before unioning
        guard !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        terms.append(trimmed)
        raw["version"] = raw["version"] ?? 1
        raw["terms"] = terms.map { ["term": $0] }
        save()
        onChange?()
    }

    private func save() {
        ConfigPaths.ensureDir()
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(
                withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        else { return }
        let tmp = ConfigPaths.configDir.appendingPathComponent(".dictionary.json.tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(ConfigPaths.dictionaryFile, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
        watch()  // rename invalidates the vnode watch; re-arm
    }

    /// Watch the file so an edit from Cadence or a text editor propagates live.
    private func watch() {
        watcher?.cancel()
        watcher = nil
        if watchedFD >= 0 { close(watchedFD); watchedFD = -1 }
        let fd = open(ConfigPaths.dictionaryFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete],
            queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.load()
            self.onChange?()
            if self.watcher?.data.contains(.rename) == true
                || self.watcher?.data.contains(.delete) == true {
                self.watch()
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        watcher = src
        watchedFD = -1  // ownership moved to the cancel handler
    }
}

/// Per-app behaviour (blueprint §19 AppRule) plus global pause.
/// {"version":1,"paused":false,"apps":{"com.slack.Slack":"rewrite_only"},"denylist":[...]}
final class SettingsStore {
    enum Mode: String {
        case full, rewriteOnly = "rewrite_only", off
    }

    private(set) var paused = false
    /// Whether the Sophia window opens on launch. On by default so a new user
    /// sees something; turned off by anyone who runs it at login.
    private(set) var showWindowAtLaunch = true
    private var apps: [String: String] = [:]
    private var denylist: [String]

    /// Password managers and credential UIs never see any part of Sophia (AC-8).
    static let builtinDenylist = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    init() {
        denylist = Self.builtinDenylist
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: ConfigPaths.settingsFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        paused = obj["paused"] as? Bool ?? false
        showWindowAtLaunch = obj["showWindowAtLaunch"] as? Bool ?? true
        apps = obj["apps"] as? [String: String] ?? [:]
        let extra = obj["denylist"] as? [String] ?? []
        denylist = Array(Set(Self.builtinDenylist + extra)).sorted()
    }

    func save() {
        ConfigPaths.ensureDir()
        let obj: [String: Any] = [
            "version": 1, "paused": paused, "apps": apps, "denylist": denylist,
            "showWindowAtLaunch": showWindowAtLaunch,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return }
        let tmp = ConfigPaths.configDir.appendingPathComponent(".settings.json.tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(ConfigPaths.settingsFile, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    func setPaused(_ value: Bool) {
        paused = value
        save()
    }

    func setShowWindowAtLaunch(_ value: Bool) {
        showWindowAtLaunch = value
        save()
    }

    func mode(for bundleID: String?) -> Mode {
        guard let bundleID else { return .off }
        if denylist.contains(bundleID) { return .off }
        if let raw = apps[bundleID], let mode = Mode(rawValue: raw) { return mode }
        return .full
    }

    func setMode(_ mode: Mode, for bundleID: String) {
        apps[bundleID] = mode.rawValue
        save()
    }

    func isDenied(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return denylist.contains(bundleID)
    }
}
