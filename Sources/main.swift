import Cocoa
import Darwin

if CommandLine.arguments.contains("--dump-stack") {
    exit(WindowDump.run())
}

// 单实例：两个实例会同时监听鼠标、同时激活窗口，互相打架。
let lockFD = open("/tmp/focusflow.lock", O_CREAT | O_RDWR, 0o644)
if lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
