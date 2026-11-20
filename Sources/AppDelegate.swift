import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let targetBundleID: String
    private var preferences = Preferences.load()
    private var history = PlaybackHistory()
    private var status: NSStatusItem!
    private var overlay: OverlaySession?
    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var settings: NSWindow?
    private var artworkPreview: NSWindow?
    private var enabled: NSButton?
    private var loop: NSButton?
    private var reduceMotion: NSButton?
    private var duration: NSSlider?
    private var durationLabel: NSTextField?
    private var opacity: NSSlider?
    private var lockFD: Int32 = -1
    private var manualPending = false
    private var manualDeadline = Date.distantPast
    private var lastStatus = "等待 Codex 窗口"
    private var stateLabel: NSTextField?

    init(targetBundleID: String) { self.targetBundleID = targetBundleID; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if (CommandLine.arguments.contains("--follow-test") || Bundle.main.bundleIdentifier == "local.codexboot.demo")
            && targetBundleID == "local.codexboot.fixture" {
            preferences.introDuration = 3600
        }
        try? FileManager.default.createDirectory(at: Preferences.directory, withIntermediateDirectories: true)
        lockFD = open(Preferences.directory.appendingPathComponent("helper.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Codex 开机动画")
        status.button?.toolTip = "Codex · \(preferences.skin.title)"
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        rebuildMenu()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                guard let self else { return }
                if name == NSWorkspace.didTerminateApplicationNotification,
                   let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier == self.targetBundleID {
                    self.history.terminate(pid: app.processIdentifier)
                    if self.overlay?.targetPID == app.processIdentifier { self.stop(reason: "target_terminated") }
                }
                self.tick()
            })
        }
        EventLog.write("helper_started", ["targetBundleID": targetBundleID, "loopBackground": preferences.loopBackground])
        schedule(0.4); tick()
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if Bundle.main.bundleIdentifier == "local.codexboot.demo" { openSettings() }
        if CommandLine.arguments.contains("--preview") { preview() }
        if let i = CommandLine.arguments.firstIndex(of: "--quit-after"),
           CommandLine.arguments.count > i + 1, let seconds = Double(CommandLine.arguments[i + 1]) {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in NSApp.terminate(nil) }
        }
    }

    private func schedule(_ newInterval: TimeInterval) {
        guard interval != newInterval else { return }
        interval = newInterval; timer?.invalidate()
        timer = Timer(timeInterval: newInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let target = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let target else {
            if overlay != nil { stop(reason: "target_not_running") }
            setState("等待 Codex 启动"); schedule(0.4); return
        }
        let windows = WindowInventory.read()
        if let active = overlay {
            active.update(windows: windows, frontmostPID: frontmost)
            schedule(frontmost == target.processIdentifier ? 1.0 / 30 : 0.4)
            return
        }
        schedule(0.4)
        guard preferences.enabled || manualPending else { setState("自动开屏已关闭"); return }
        if manualPending && Date() > manualDeadline { manualPending = false }
        guard frontmost == target.processIdentifier,
              let window = WindowSelection.select(windows, pid: target.processIdentifier) else {
            setState("等待 Codex 前台窗口"); return
        }
        guard manualPending || !history.contains(pid: target.processIdentifier, window: window.id) else {
            setState("就绪 · 此窗口已播放"); return
        }
        history.mark(pid: target.processIdentifier, window: window.id)
        manualPending = false
        let session = OverlaySession(target: window, preferences: preferences)
        overlay = session
        session.onFinish = { [weak self, weak session] in
            guard let self, self.overlay === session else { return }
            self.overlay = nil; self.setState("就绪 · 播放已结束"); self.schedule(0.4)
        }
        setState("跟随窗口 \(window.id)")
        session.update(windows: windows, frontmostPID: frontmost)
        schedule(1.0 / 30)
    }

    private func setState(_ text: String) {
        guard lastStatus != text else { return }
        lastStatus = text; stateLabel?.stringValue = text
        EventLog.write("state", ["message": text])
        status?.button?.toolTip = "Codex · \(text)"
    }
    private func stop(reason: String) {
        manualPending = false
        overlay?.finish(reason: reason); overlay = nil
    }
    @objc func preview() {
        stop(reason: "preview_restart")
        guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first else {
            setState("请先打开 Codex，再点播放"); openSettings(); return
        }
        manualPending = true; manualDeadline = Date().addingTimeInterval(10)
        target.activate(options: [.activateIgnoringOtherApps]); tick()
    }
    @objc private func stopNow() { stop(reason: "menu_stop") }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleEnabled() {
        preferences.enabled.toggle(); preferences.save()
        if !preferences.enabled { stop(reason: "disabled") }
        rebuildMenu(); refreshSettings()
    }
    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }
    private func rebuildMenu() {
        guard let menu = status?.menu else { return }
        menu.removeAllItems()
        let header = menu.addItem(withTitle: "Codex · \(preferences.skin.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let skins = NSMenu(title: "皮肤")
        for skin in Skin.allCases {
            let item = skins.addItem(withTitle: skin.title, action: #selector(changeSkin(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = skin.rawValue
            item.state = skin == preferences.skin ? .on : .off
        }
        menu.addItem(withTitle: "皮肤", action: nil, keyEquivalent: "").submenu = skins
        let item = menu.addItem(withTitle: "自动播放开屏", action: #selector(toggleEnabled), keyEquivalent: "")
        item.target = self; item.state = preferences.enabled ? .on : .off
        menu.addItem(.separator())
        for (title, action) in [("播放一次开屏", #selector(preview)), ("立即关闭动画", #selector(stopNow)),
                                ("设置…", #selector(openSettings)), ("退出", #selector(quit))] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
    }

    @objc private func changeSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let skin = Skin(rawValue: id), skin != preferences.skin else { return }
        stop(reason: "skin_changed")
        artworkPreview?.close()
        preferences.select(skin); preferences.save()
        status.button?.toolTip = "Codex · \(skin.title)"
        settings?.title = "Codex · \(skin.title)"
        refreshSettings()
    }

    @objc func openSettings() {
        if settings == nil { createSettings() }
        refreshSettings(); settings?.center(); settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func createSettings() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 390),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Codex · \(preferences.skin.title)"; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        let title = NSTextField(labelWithString: "开屏设置")
        title.font = .systemFont(ofSize: 21, weight: .medium)
        stack.addArrangedSubview(title)
        stateLabel = NSTextField(labelWithString: lastStatus)
        stateLabel?.textColor = .secondaryLabelColor; stack.addArrangedSubview(stateLabel!)
        enabled = NSButton(checkboxWithTitle: "Codex 打开新窗口时播放开屏", target: self, action: #selector(settingsChanged))
        loop = NSButton(checkboxWithTitle: "开屏后保留淡淡的动态背景", target: self, action: #selector(settingsChanged))
        reduceMotion = NSButton(checkboxWithTitle: "减少动态效果", target: self, action: #selector(settingsChanged))
        for control in [enabled!, loop!, reduceMotion!] { stack.addArrangedSubview(control) }
        durationLabel = NSTextField(labelWithString: "")
        stack.addArrangedSubview(durationLabel!)
        duration = NSSlider(value: preferences.introDuration, minValue: 2, maxValue: preferences.skin.filmDuration,
                            target: self, action: #selector(settingsChanged))
        duration?.widthAnchor.constraint(equalToConstant: 350).isActive = true
        stack.addArrangedSubview(duration!)
        stack.addArrangedSubview(NSTextField(labelWithString: "动态背景浓度（0–30%）"))
        opacity = NSSlider(value: preferences.backgroundOpacity, minValue: 0, maxValue: 0.3,
                          target: self, action: #selector(settingsChanged))
        opacity?.widthAnchor.constraint(equalToConstant: 350).isActive = true
        stack.addArrangedSubview(opacity!)
        let actions = NSStackView(views: [ActionButton("播放一次", action: { [weak self] in self?.preview() }),
                                         ActionButton("关闭动画", action: { [weak self] in self?.stopNow() }),
                                         ActionButton("完整预览", action: { [weak self] in self?.previewArtwork() })])
        actions.spacing = 10; stack.addArrangedSubview(actions)
        let note = NSTextField(wrappingLabelWithString: "默认只播放短开屏。切换应用或最小化时暂停并隐藏；不修改 Codex，也不读取窗口内容。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 350; stack.addArrangedSubview(note)
        window.contentView = stack; settings = window
    }
    private func previewArtwork() {
        if let window = artworkPreview {
            window.makeKeyAndOrderFront(nil)
            (window.contentView as? AnimationView)?.replay()
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 1120, height: 630),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "\(preferences.skin.title) · 动画预览"; window.isReleasedWhenClosed = false
        let view = AnimationView(frame: NSRect(x: 0, y: 0, width: 1120, height: 630), skin: preferences.skin, reducedMotion: preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, fullPreview: true)
        view.skip.handler = { [weak window] in window?.close() }
        window.contentView = view; window.delegate = self; artworkPreview = window
        view.onIntroEnded = { [weak view] in view?.pause(true) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        view.pause(false)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === artworkPreview else { return }
        (window.contentView as? AnimationView)?.pause(true)
        artworkPreview = nil
    }
    private func refreshSettings() {
        enabled?.state = preferences.enabled ? .on : .off
        loop?.state = preferences.loopBackground ? .on : .off
        reduceMotion?.state = preferences.reducedMotion ? .on : .off
        duration?.maxValue = preferences.skin.filmDuration
        duration?.doubleValue = preferences.introDuration
        durationLabel?.stringValue = String(format: "开屏时长 · %.1f 秒", preferences.introDuration)
        opacity?.doubleValue = preferences.backgroundOpacity
        opacity?.isEnabled = preferences.loopBackground
        stateLabel?.stringValue = lastStatus
    }
    @objc private func settingsChanged() {
        preferences.enabled = enabled?.state == .on
        preferences.loopBackground = loop?.state == .on
        preferences.reducedMotion = reduceMotion?.state == .on
        preferences.introDuration = duration?.doubleValue ?? preferences.skin.filmDuration
        preferences.backgroundOpacity = opacity?.doubleValue ?? 0.1
        preferences.save(); refreshSettings(); rebuildMenu()
        // Apply changes on the next playback; closing the active overlay avoids
        // leaving a loop running after its switch is turned off.
        stop(reason: "settings_changed")
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        stop(reason: "helper_quit"); timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if lockFD >= 0 { close(lockFD) }
        EventLog.write("helper_stopped")
    }
}
