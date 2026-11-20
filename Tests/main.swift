import AppKit

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("FAIL: \(description)") }
    checks += 1; print("PASS: \(description)")
}
func window(_ id: CGWindowID, _ pid: pid_t = 42, _ width: CGFloat = 900,
            _ height: CGFloat = 600, layer: Int = 0, alpha: Double = 1) -> TrackedWindow {
    TrackedWindow(id: id, pid: pid, frame: CGRect(x: 20, y: 30, width: width, height: height),
                  layer: layer, alpha: alpha)
}
let front = window(1, 42, 700)
let larger = window(2, 42, 1400)
expect(WindowSelection.select([front, larger], pid: 42)?.id == 1, "choose front window, not largest")
expect(WindowSelection.select([larger, front], pid: 42, pinned: 1)?.id == 1, "pin survives z-order change")
expect(WindowSelection.select([larger], pid: 42, pinned: 1) == nil, "missing pinned window never switches documents")
expect(WindowSelection.select([window(3, 77), front], pid: 42)?.id == 1, "exclude other applications")
expect(WindowSelection.select([window(3, layer: 3), front], pid: 42)?.id == 1, "exclude floating panels")
expect(WindowSelection.select([window(3, alpha: 0), front], pid: 42)?.id == 1, "exclude invisible windows")
expect(WindowSelection.select([window(3, 42, 200, 100), front], pid: 42)?.id == 1, "exclude small popovers")
let flipped = WindowSelection.cocoaFrame(CGRect(x: -1400, y: -400, width: 1000, height: 700), primaryHeight: 900)
expect(flipped == CGRect(x: -1400, y: 600, width: 1000, height: 700), "convert negative external display coordinates")
var history = PlaybackHistory()
history.mark(pid: 42, window: 1)
expect(history.contains(pid: 42, window: 1), "returning to same window doesn't replay")
expect(!history.contains(pid: 42, window: 2), "a new window can play an intro")
expect(!history.contains(pid: 77, window: 1), "window ID alone doesn't identify process")
history.terminate(pid: 42)
expect(!history.contains(pid: 42, window: 1), "process termination resets playback history")
print("\(checks) checks passed")
