import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var clicks = 0
    var label: NSTextField!
    var scenarioTimers: [Timer] = []
    func applicationDidFinishLaunching(_ notification: Notification) { makeWindow() }
    @objc func makeWindow() {
        let window = NSWindow(contentRect: NSRect(x: 180, y: 200, width: 1000, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Codex Boot · 跟随测试 \(windows.count + 1)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 300)
        window.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        let title = NSTextField(labelWithString: "WINDOW FOLLOW LAB")
        title.font = .monospacedSystemFont(ofSize: 24, weight: .medium); title.textColor = .systemMint
        stack.addArrangedSubview(title)
        label = NSTextField(labelWithString: "这是独立测试窗口，不会操作 Codex 的内容。")
        label.textColor = .white; stack.addArrangedSubview(label)
        for (title, action) in [("移动窗口", #selector(moveWindow)), ("缩放窗口", #selector(resizeWindow)),
                                ("新建第二窗口", #selector(makeWindow)), ("点击计数", #selector(countClick)),
                                ("运行跟随验收", #selector(runScenario)),
                                ("最小化", #selector(minimize)), ("退出测试窗口", #selector(quit))] {
            let button = NSButton(title: title, target: self, action: action)
            stack.addArrangedSubview(button)
        }
        window.contentView = stack
        windows.append(window); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func moveWindow() {
        guard let window = NSApp.keyWindow else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 80, y: window.frame.minY - 40))
    }
    @objc func resizeWindow() {
        guard let window = NSApp.keyWindow else { return }
        window.setContentSize(NSSize(width: window.frame.width - 100, height: window.frame.height - 70))
    }
    @objc func countClick() { clicks += 1; label.stringValue = "点击成功：\(clicks)" }
    @objc func minimize() { NSApp.keyWindow?.miniaturize(nil) }
    @objc func runScenario() {
        guard let first = windows.first else { return }
        for timer in scenarioTimers { timer.invalidate() }; scenarioTimers = []
        let steps: [(Double, () -> Void)] = [
            (1, { first.deminiaturize(nil); first.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }),
            (2, { first.setFrameOrigin(NSPoint(x: 280, y: 260)) }),
            (3, { first.setContentSize(NSSize(width: 820, height: 540)) }),
            (4, { first.miniaturize(nil) }),
            (5, { first.deminiaturize(nil); first.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }),
            (6, { self.makeWindow() }),
            (7, { first.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }),
            (8, { self.label.stringValue = "跟随验收已完成 · 请检查浮层日志" })
        ]
        for (seconds, action) in steps {
            scenarioTimers.append(Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in action() })
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = windows.first { window.deminiaturize(nil); window.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true); return true
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = FixtureDelegate(); app.delegate = delegate
app.run()
