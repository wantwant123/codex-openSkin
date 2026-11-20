import AppKit

enum Skin: String, CaseIterable {
    case dragon = "DragonCodex"
    case emerald = "EmeraldAwakening"
    var title: String { self == .dragon ? "Dragon Codex" : "翡翠觉醒" }
    var filmDuration: Double { self == .dragon ? 14 : 11 }
}

struct Preferences: Codable {
    var enabled = true
    var loopBackground = false
    var backgroundOpacity = 0.10
    var introDuration = Skin.dragon.filmDuration
    private var skinID: String? = Skin.dragon.rawValue
    var skin: Skin { skinID.flatMap(Skin.init(rawValue:)) ?? .dragon }

    mutating func select(_ next: Skin) {
        introDuration = introDuration == skin.filmDuration ? next.filmDuration : min(introDuration, next.filmDuration)
        skinID = next.rawValue
    }
    var reducedMotion = false
    var timingVersion: Int? = 1

    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_BOOT_DATA_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexBootAnimation")
    }
    static var url: URL { directory.appendingPathComponent("settings.json") }
    static func load() -> Preferences {
        guard let data = try? Data(contentsOf: url),
              var value = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        value.backgroundOpacity = min(0.3, max(0, value.backgroundOpacity))
        if value.skinID == nil && (value.introDuration == 11 || (value.timingVersion == nil && value.introDuration == 9.6)) {
            value.introDuration = Skin.dragon.filmDuration
        }
        value.skinID = value.skin.rawValue
        value.timingVersion = 1
        value.introDuration = min(value.skin.filmDuration, max(2, value.introDuration))
        return value
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Self.url, options: .atomic)
        } catch { EventLog.write("settings_error", ["error": error.localizedDescription]) }
    }
}

enum EventLog {
    static let url = Preferences.directory.appendingPathComponent("events.jsonl")
    static func write(_ event: String, _ fields: [String: Any] = [:]) {
        var entry = fields
        entry["event"] = event
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        var line = data; line.append(10)
        try? FileManager.default.createDirectory(at: Preferences.directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        // Keep diagnostics bounded. No titles, screenshots, text, or window contents.
        if let size = try? handle.seekToEnd(), size > 1_048_576 {
            try? handle.truncate(atOffset: 0); try? handle.seek(toOffset: 0)
        }
        try? handle.write(contentsOf: line); try? handle.close()
    }
    static func frame(_ value: CGRect) -> [String: Double] {
        ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
    }
}

final class ActionButton: NSButton {
    var handler: (() -> Void)?
    convenience init(_ title: String, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        handler = action; target = self; self.action = #selector(invoke)
    }
    @objc private func invoke() { handler?() }
}

final class SkipButton: NSButton {
    var handler: (() -> Void)?
    convenience init(action: @escaping () -> Void) {
        self.init(title: "跳过", target: nil, action: nil)
        handler = action; target = self; self.action = #selector(invoke)
        isBordered = false
    }
    @objc private func invoke() { handler?() }
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 13, yRadius: 13)
        NSColor.black.withAlphaComponent(isHighlighted ? 0.85 : 0.65).setFill(); pill.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke(); pill.lineWidth = 0.7; pill.stroke()
        let text = NSAttributedString(string: "跳过", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
