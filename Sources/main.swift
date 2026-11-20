import AppKit

let demo = CommandLine.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "local.codexboot.demo"
if demo && ProcessInfo.processInfo.environment["CODEX_BOOT_DATA_DIR"] == nil {
    let directory = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("output/follow-test").path
    setenv("CODEX_BOOT_DATA_DIR", directory, 1)
}
let target = demo ? "local.codexboot.fixture" : "com.openai.codex"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(targetBundleID: target)
app.delegate = delegate
app.run()
