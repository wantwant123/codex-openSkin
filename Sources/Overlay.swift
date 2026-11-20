import AppKit

final class OverlaySession {
    enum Phase { case intro, background, fading, finished }
    let targetPID: pid_t
    let targetID: CGWindowID
    let panel: NSPanel
    let scene: AnimationView
    private let skipPanel: NSPanel
    private(set) var phase = Phase.intro
    private var elapsed: TimeInterval = 0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var visible = false
    private var frame = CGRect.zero
    private let preferences: Preferences
    private var missingSince: TimeInterval?
    private var fadeTimer: Timer?
    var onFinish: (() -> Void)?

    init(target: TrackedWindow, preferences: Preferences) {
        targetPID = target.pid; targetID = target.id; self.preferences = preferences
        let rect = WindowSelection.cocoaFrame(target.frame, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        panel.ignoresMouseEvents = true
        scene = AnimationView(frame: NSRect(origin: .zero, size: rect.size), skin: preferences.skin,
                              reducedMotion: preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                              duration: preferences.introDuration)
        panel.contentView = scene
        scene.skip.isHidden = true
        skipPanel = NSPanel(contentRect: NSRect(x: rect.maxX - 104, y: rect.maxY - 72, width: 84, height: 28),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        skipPanel.isOpaque = false; skipPanel.backgroundColor = .clear
        skipPanel.hasShadow = false; skipPanel.hidesOnDeactivate = false
        skipPanel.level = .floating; skipPanel.isReleasedWhenClosed = false
        skipPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let skip = SkipButton(action: {})
        skip.bezelStyle = .rounded
        skip.handler = { [weak self] in self?.reveal(reason: "skip") }
        skipPanel.contentView = skip
        if preferences.introDuration <= preferences.skin.filmDuration {
            scene.onIntroEnded = { [weak self] in self?.reveal(reason: "intro_complete") }
        }
        panel.addChildWindow(skipPanel, ordered: .above)
        scene.pause(true)
        EventLog.write("overlay_created", ["pid": target.pid, "window": target.id])
    }

    func update(windows: [TrackedWindow], frontmostPID: pid_t?) {
        guard phase != .finished else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(now - lastTick, 0.2); lastTick = now
        guard let target = WindowSelection.select(windows, pid: targetPID, pinned: targetID) else {
            setVisible(false, reason: "window_offscreen")
            if missingSince == nil { missingSince = now }
            // Keep playback paused through a normal minimize/restore. A closed
            // window expires, so it cannot hold the helper indefinitely.
            if now - (missingSince ?? now) > 30 { finish(reason: "window_timeout") }
            return
        }
        missingSince = nil
        let rect = WindowSelection.cocoaFrame(target.frame, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
        if rect != frame {
            frame = rect; panel.setFrame(rect, display: true)
            skipPanel.setFrameOrigin(NSPoint(x: rect.maxX - 104, y: rect.maxY - 72))
            EventLog.write("follow", ["window": targetID, "target": EventLog.frame(rect),
                                      "overlay": EventLog.frame(panel.frame)])
        }
        // If another document/dialog takes front position, don't cover it.
        let top = windows.first { $0.pid == targetPID && $0.layer == 0 && $0.alpha > 0 &&
            $0.frame.width >= 100 && $0.frame.height >= 80 }
        let shouldShow = frontmostPID == targetPID && top?.id == targetID
        let wasVisible = visible
        setVisible(shouldShow, reason: shouldShow ? "target_frontmost" : "another_window_frontmost")
        if shouldShow && wasVisible && phase == .intro {
            elapsed += delta
            // Time the reveal to the actual final movie frame. The longer
            // deadline also recovers from a decoder that never becomes ready.
            let deadline = preferences.introDuration + (scene.hasMovie ? 3 : 0)
            if elapsed >= deadline { reveal(reason: "intro_complete") }
        }
    }

    private func setVisible(_ show: Bool, reason: String) {
        guard visible != show else { return }
        visible = show; scene.pause(!show)
        if show {
            panel.orderFrontRegardless()
            if phase == .intro { skipPanel.orderFrontRegardless() }
        } else { skipPanel.orderOut(nil); panel.orderOut(nil) }
        EventLog.write(show ? "overlay_visible" : "overlay_hidden", ["reason": reason, "window": targetID])
    }

    func reveal(reason: String) {
        guard phase == .intro else { return }
        panel.ignoresMouseEvents = true
        panel.removeChildWindow(skipPanel); skipPanel.orderOut(nil)
        if preferences.loopBackground {
            scene.enterBackground()
            phase = .background
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.65
                panel.animator().alphaValue = preferences.backgroundOpacity
            }
            EventLog.write("background_started", ["window": targetID, "clickThrough": true])
        } else {
            scene.silence()
            phase = .fading
            EventLog.write("fade_started", ["reason": reason, "window": targetID, "clickThrough": true])
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.65; panel.animator().alphaValue = 0
            }
            fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                self?.finish(reason: reason)
            }
        }
    }

    func finish(reason: String) {
        guard phase != .finished else { return }
        scene.pause(true)
        phase = .finished; fadeTimer?.invalidate(); fadeTimer = nil
        panel.removeChildWindow(skipPanel); skipPanel.orderOut(nil); skipPanel.close()
        panel.orderOut(nil); panel.close()
        EventLog.write("overlay_finished", ["reason": reason, "window": targetID])
        onFinish?(); onFinish = nil
    }
    deinit { fadeTimer?.invalidate() }
}
