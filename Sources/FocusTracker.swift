import Cocoa
import ApplicationServices
import Carbon

private let focusChangedCallback: AXObserverCallback = { _, element, _, userData in
    guard let userData = userData else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(userData).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    DispatchQueue.main.async {
        tracker.recordFocus(for: pid)
    }
}

/// ProcessSerialNumber 的 Swift 等价结构（两个 UInt32）。
/// 放在文件作用域，@convention(c) 函数指针才认。
struct PSN {
    var high: UInt32 = 0
    var low: UInt32 = 0
}

final class FocusTracker {
    private struct Entry {
        let pid: pid_t
        let window: AXUIElement
    }

    private var lastFocusedByDisplay: [CGDirectDisplayID: Entry] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    // After we activate or raise a window in pid X, that app frequently emits its own
    // focus-change notifications as it settles (e.g. Chrome auto-flipping its main window).
    // Ignore recordFocus from X for a short window so those knock-on events don't overwrite
    // entries that the user genuinely set by clicking.
    private var suppressUntil: [pid_t: Date] = [:]
    private let suppressionDuration: TimeInterval = 0.1

    private let logPath = "/tmp/autofocusmonitor.log"
    private func log(_ s: String) {
        let line = "[\(Date())] \(s)\n"
        if let data = line.data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: logPath) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    private func appName(_ pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid\(pid)"
    }

    private func logDisplayLayout() {
        // Dump all CGDisplays with bounds.
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        for i in 0..<Int(count) {
            let id = ids[i]
            let b = CGDisplayBounds(id)
            log("CGDisplay \(id): bounds=(\(b.origin.x),\(b.origin.y) \(b.size.width)x\(b.size.height))")
        }
        // Dump NSScreens with their reported NSScreenNumber so we can spot mismatches.
        for (i, screen) in NSScreen.screens.enumerated() {
            let n = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            log("NSScreen[\(i)] NSScreenNumber=\(n) frame=(\(screen.frame.origin.x),\(screen.frame.origin.y) \(screen.frame.size.width)x\(screen.frame.size.height))")
        }
    }

    private func isUserWindow(_ window: AXUIElement) -> Bool {
        // Allow standard windows, dialogs, and similar interactive popups. We used to
        // require kAXStandardWindowSubrole, which dropped real save/confirm dialogs the
        // user genuinely focuses. Keep the size + title checks below — those still filter
        // out transient ghosts (Chrome's split-tab drag previews etc.) without rejecting
        // legitimate popups.
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""
        if title.isEmpty { return false }

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        if let val = sizeRef {
            var size = CGSize.zero
            AXValueGetValue(val as! AXValue, .cgSize, &size)
            if size.width < 50 || size.height < 50 { return false }
        }
        return true
    }

    private func windowTitle(_ window: AXUIElement) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &ref)
        return (ref as? String) ?? "(no title)"
    }

    func start() {
        logDisplayLayout()
        for runningApp in NSWorkspace.shared.runningApplications where runningApp.activationPolicy == .regular {
            attachObserver(for: runningApp.processIdentifier)
            recordFocus(for: runningApp.processIdentifier)
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.attachObserver(for: app.processIdentifier)
            }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.detachObserver(for: app.processIdentifier)
            }
        }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            self?.log("SPACE CHANGED（系统切换了桌面），当前前台=\(front)")
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.recordFocus(for: app.processIdentifier)
            }
        }
    }

    private func attachObserver(for pid: pid_t) {
        guard observers[pid] == nil, pid > 0 else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(pid, focusChangedCallback, &observer)
        guard result == .success, let obs = observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, appElement, kAXFocusedWindowChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXMainWindowChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, appElement, kAXWindowMovedNotification as CFString, selfPtr)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observers[pid] = obs
    }

    private func detachObserver(for pid: pid_t) {
        if let obs = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        for (k, v) in lastFocusedByDisplay where v.pid == pid {
            lastFocusedByDisplay.removeValue(forKey: k)
        }
    }

    func recordFocus(for pid: pid_t) {
        if let until = suppressUntil[pid], Date() < until {
            return
        }
        let appEl = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef)
        guard res == .success, let win = winRef else { return }
        let window = win as! AXUIElement

        // Filter out transient/ghost windows that Chrome (and others) briefly focus during
        // operations like split-tab — drag previews, popups, drawers, sheets. Tracking them
        // pollutes our state because they aren't windows the user actually wants restored.
        if !isUserWindow(window) {
            return
        }

        guard let displayID = displayID(for: window) else { return }

        // The same window can only live on one display. Drop any stale references
        // to this window that other displays may be holding (e.g. user dragged it across).
        let staleKeys = lastFocusedByDisplay.compactMap { (k, v) -> CGDirectDisplayID? in
            (k != displayID && CFEqual(v.window, window)) ? k : nil
        }
        for k in staleKeys {
            lastFocusedByDisplay.removeValue(forKey: k)
        }

        lastFocusedByDisplay[displayID] = Entry(pid: pid, window: window)
    }

    private func validatedEntry(for displayID: CGDirectDisplayID) -> Entry? {
        guard let entry = lastFocusedByDisplay[displayID] else { return nil }
        guard isWindowAlive(entry.window),
              self.displayID(for: entry.window) == displayID else {
            lastFocusedByDisplay.removeValue(forKey: displayID)
            return nil
        }
        return entry
    }

    /// Called when the user releases a mouse drag. The currently-focused window of the
    /// frontmost app is whatever window they just dropped onto this display — record it
    /// as the new entry so the next cross doesn't reactivate the stale previous-frontmost.
    func recordDroppedWindow(on displayID: CGDirectDisplayID) {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let pid = front.processIdentifier
        guard let window = focusedWindow(of: pid) else { return }
        guard isUserWindow(window) else { return }
        guard self.displayID(for: window) == displayID else { return }
        lastFocusedByDisplay[displayID] = Entry(pid: pid, window: window)
        log("dropped window recorded for display \(displayID): \(appName(pid)):'\(windowTitle(window))'")
    }

    func activateLastWindow(on displayID: CGDirectDisplayID) {
        log("跨屏 → 屏幕 \(displayID)")
        guard let top = topmostWindowInfo(on: displayID) else {
            log("该屏没有可用窗口，跳过")
            return
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == top.pid {
            // App 已经是前台的：只要把这块屏上的窗口设成它的主窗口即可
            focusWindow(pid: top.pid, matching: top.rect, displayID: displayID)
            return
        }
        let tops = snapshotTopWindows()
        let activated = activateFrontWindowOnly(pid: top.pid)
            || (NSRunningApplication(processIdentifier: top.pid)?.activate() ?? false)
        log("聚焦 \(appName(top.pid))（仅前窗口=\(activated)）")
        // 关键：把「这块屏上的那个窗口」设成该 App 的焦点窗口/主窗口，
        // 否则 App 的 key window 还留在别的屏，状态栏就亮在别的屏上。
        focusWindow(pid: top.pid, matching: top.rect, displayID: displayID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.restoreOtherDisplays(tops, target: displayID)
        }
    }

    private func focusWindow(pid: pid_t, matching rect: CGRect, displayID: CGDirectDisplayID? = nil) {
        let appEl = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return }
        var best: AXUIElement?
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for w in windows {
            guard let f = windowFrame(w) else { continue }
            let delta = abs(f.minX - rect.minX) + abs(f.minY - rect.minY)
                + abs(f.width - rect.width) + abs(f.height - rect.height)
            if delta < bestDelta {
                bestDelta = delta
                best = w
            }
        }
        guard let target = best else { return }
        AXUIElementSetAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, target)
        AXUIElementSetAttributeValue(appEl, kAXMainWindowAttribute as CFString, target)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        if let f = windowFrame(target) {
            var ids = [CGDirectDisplayID](repeating: 0, count: 4)
            var count: UInt32 = 0
            _ = CGGetDisplaysWithRect(f, 4, &ids, &count)
            let got = count > 0 ? "\(ids[0])" : "?"
            let want = displayID.map { "\($0)" } ?? "?"
            log("已设为焦点窗口（所在屏=\(got) 目标屏=\(want) delta=\(Int(bestDelta))）")
        }
    }

    private struct TopWindowInfo {
        let pid: pid_t
        let rect: CGRect
        let name: String
    }

    private func topmostWindowInfo(on displayID: CGDirectDisplayID) -> TopWindowInfo? {
        let bounds = CGDisplayBounds(displayID)
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                              width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard rect.width > 100, rect.height > 60 else { continue }
            guard bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let name = (w[kCGWindowOwnerName as String] as? String) ?? "?"
            return TopWindowInfo(pid: pid, rect: rect, name: name)
        }
        return nil
    }

    // MARK: - 层序还原（非目标屏绝不允许变）

    private struct TopWindow {
        let display: CGDirectDisplayID
        let windowID: UInt32
        let pid: pid_t
        let name: String
    }

    private typealias CGSMainConnectionIDFn = @convention(c) () -> Int32
    private typealias CGSOrderWindowFn = @convention(c) (Int32, Int32, UInt32, UInt32) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static let mainConnectionID: CGSMainConnectionIDFn? = {
        guard let h = skyLight, let sym = dlsym(h, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: CGSMainConnectionIDFn.self)
    }()
    private static let orderWindow: CGSOrderWindowFn? = {
        guard let h = skyLight, let sym = dlsym(h, "CGSOrderWindow") else { return nil }
        return unsafeBitCast(sym, to: CGSOrderWindowFn.self)
    }()

    /// 记录每块屏当前最上面那个窗口。
    private func snapshotTopWindows() -> [TopWindow] {
        var result: [TopWindow] = []
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = num.uint32Value
            let bounds = CGDisplayBounds(display)
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]]) ?? []
            for w in list {
                guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                                  width: b["Width"] ?? 0, height: b["Height"] ?? 0)
                guard bounds.contains(CGPoint(x: rect.midX, y: rect.midY)),
                      rect.width > 100, rect.height > 60 else { continue }
                let wid = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
                let pid = (w[kCGWindowOwnerPID as String] as? pid_t) ?? 0
                let name = (w[kCGWindowOwnerName as String] as? String) ?? "?"
                result.append(TopWindow(display: display, windowID: wid, pid: pid, name: name))
                break
            }
        }
        return result
    }

    /// 激活会让这个 App 在所有屏上的窗口浮上来；把非目标屏的顶层窗口按原样放回去。
    private func restoreOtherDisplays(_ tops: [TopWindow], target: CGDirectDisplayID) {
        guard let getConn = FocusTracker.mainConnectionID,
              let order = FocusTracker.orderWindow else {
            log("层序还原不可用：SkyLight 符号没找到")
            return
        }
        let cid = getConn()
        for top in tops {
            if top.display == target { continue }
            // 现在这块屏最上面是谁？
            let now = snapshotTopWindows().first { $0.display == top.display }
            guard let current = now else { continue }
            if current.windowID == top.windowID { continue }
            // 原来的顶层窗口被顶下去了，按原样放回最上面
            let err = order(cid, 1, top.windowID, 0)
            log("恢复层序：屏幕 \(top.display) 顶层回到 \(top.name)（err=\(err)）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                let after = self.snapshotTopWindows().first { $0.display == top.display }
                let ok = after?.windowID == top.windowID
                let stateText = ok ? "已还原" : "仍未还原"
                let currentName = after?.name ?? "?"
                self.log("层序复核：屏幕 \(top.display) \(stateText)（当前=\(currentName)）")
            }
        }
    }

    /// 只把这个 App 的「前窗口」提到前面，不动它在别的显示器上的窗口。
    /// Carbon 的 SetFrontProcessWithOptions + kSetFrontProcessFrontWindowOnly 就是干这个的。
    private typealias GetProcessForPIDFn = @convention(c) (Int32, UnsafeMutableRawPointer) -> Int32
    private typealias SetFrontProcessWithOptionsFn = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int32

    private static let carbonHandle = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_NOW)
    private static let getPSN: GetProcessForPIDFn? = {
        guard let h = carbonHandle, let sym = dlsym(h, "GetProcessForPID") else { return nil }
        return unsafeBitCast(sym, to: GetProcessForPIDFn.self)
    }()
    private static let setFrontOnly: SetFrontProcessWithOptionsFn? = {
        guard let h = carbonHandle, let sym = dlsym(h, "SetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(sym, to: SetFrontProcessWithOptionsFn.self)
    }()

    private func activateFrontWindowOnly(pid: pid_t) -> Bool {
        guard let getPSN = FocusTracker.getPSN, let setFront = FocusTracker.setFrontOnly else { return false }
        var psn = PSN()
        let got = withUnsafeMutableBytes(of: &psn) { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return getPSN(pid, base)
        }
        guard got == 0 else { return false }
        // kSetFrontProcessFrontWindowOnly = 0x1
        let set = withUnsafeMutableBytes(of: &psn) { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return setFront(base, 0x1)
        }
        return set == 0
    }

    /// 激活这个 App 会不会把它在别的屏上的窗口顶上来。
    private func appWouldReorderOtherDisplays(pid: pid_t, except target: CGDirectDisplayID) -> Bool {
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = num.uint32Value
            if display == target { continue }
            guard hasVisibleWindow(pid: pid, on: display) else { continue }
            if let top = topmostPID(on: display), top != pid {
                return true
            }
        }
        return false
    }

    private func hasVisibleWindow(pid: pid_t, on displayID: CGDirectDisplayID) -> Bool {
        let bounds = CGDisplayBounds(displayID)
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                              width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) { return true }
        }
        return false
    }

    /// 这块屏最前面（z 序最高）的普通窗口属于哪个进程。
    private func topmostPID(on displayID: CGDirectDisplayID) -> pid_t? {
        let bounds = CGDisplayBounds(displayID)
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                              width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard bounds.contains(center), rect.width > 100, rect.height > 60 else { continue }
            if let pid = w[kCGWindowOwnerPID as String] as? pid_t {
                return pid
            }
        }
        return nil
    }

    private func resolveLiveWindow(pid: pid_t, on displayID: CGDirectDisplayID, hint: AXUIElement) -> AXUIElement {
        // If the hint is still alive and on the right display, prefer it (preserves the
        // user's exact click choice across crosses).
        if isWindowAlive(hint), self.displayID(for: hint) == displayID, isUserWindow(hint) {
            return hint
        }
        // Otherwise enumerate the app's current windows and pick whichever is on the target
        // display. This handles cases where the app rebuilt its window list internally and
        // our stored reference is stale or referring to a different window than what's
        // currently visible.
        let appEl = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
           let windows = ref as? [AXUIElement] {
            for w in windows where isUserWindow(w) && self.displayID(for: w) == displayID {
                return w
            }
        }
        return hint
    }

    private func bringWindowForward(pid: pid_t, window: AXUIElement) {
        let before = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        log("bringWindowForward \(appName(pid)):'\(windowTitle(window))'（切换前前台=\(before)）")
        suppressUntil[pid] = Date().addingTimeInterval(suppressionDuration)
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        applyMainWindowSetters(appEl: appEl, window: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            NSRunningApplication(processIdentifier: pid)?.activate()
            // Immediate post-active correction for apps that ignore setters during their
            // own activate-time logic (VS Code / Electron). When this lands fast enough,
            // there's no visible wrong-window flash.
            self?.applyMainWindowSetters(appEl: appEl, window: window)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            // Conditional retry: only fire if VS Code's restore was still in flight and
            // ate our immediate correction. This way the no-flicker path stays no-flicker
            // and we only pay the brief flash when the race goes the other way.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                guard let self = self,
                      let actual = self.focusedWindow(of: pid) else { return }
                if CFEqual(actual, window) {
                    self.log("  100ms check OK: '\(self.windowTitle(actual))'")
                    return
                }
                self.log("  100ms check MISMATCH: wanted='\(self.windowTitle(window))' got='\(self.windowTitle(actual))' — retrying")
                self.applyMainWindowSetters(appEl: appEl, window: window)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    if let final = self.focusedWindow(of: pid) {
                        let ok = CFEqual(final, window)
                        self.log("  final: \(ok ? "OK" : "STILL MISMATCH") '\(self.windowTitle(final))'")
                    }
                }
            }
        }
    }

    private func applyMainWindowSetters(appEl: AXUIElement, window: AXUIElement) {
        AXUIElementSetAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(appEl, kAXMainWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

@discardableResult
    private func activateTopmostWindow(on displayID: CGDirectDisplayID) -> pid_t? {
        let bounds = CGDisplayBounds(displayID)
        let infoList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in infoList {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bDict = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: bDict["X"] ?? 0, y: bDict["Y"] ?? 0,
                              width: bDict["Width"] ?? 0, height: bDict["Height"] ?? 0)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if bounds.contains(center) {
                if let pid = w[kCGWindowOwnerPID as String] as? pid_t {
                    NSRunningApplication(processIdentifier: pid)?.activate()
                    return pid
                }
            }
        }
        return nil
    }

    private func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef)
        guard res == .success, let w = winRef else { return nil }
        return (w as! AXUIElement)
    }

    /// 这个 App 是否在「别的显示器 + 不在当前桌面」上还有窗口。
    /// 有的话，activate() 会把那块屏也切到它的空间，用户就会看到桌面滑走。
    private func appHasWindowsOffscreenElsewhere(pid: pid_t, displayID: CGDirectDisplayID,
                                                 except target: AXUIElement) -> Bool {
        let appEl = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return false }
        for w in windows {
            if CFEqual(w, target) { continue }
            guard isUserWindow(w) else { continue }
            guard let d = self.displayID(for: w), d != displayID else { continue }
            if !isWindowOnCurrentSpace(pid: pid, window: w) {
                return true
            }
        }
        return false
    }

    /// 目标窗口是否在当前 Space 上可见。
    /// 判据：CGWindowList 的 onScreenOnly 列表里能找到同 pid、同位置、同尺寸的窗口。
    /// 在别的 Space / 最小化的窗口不在这个列表里。
    private func isWindowOnCurrentSpace(pid: pid_t, window: AXUIElement) -> Bool {
        guard let target = windowFrame(window) else { return true }   // 读不到就放行，别误伤
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid else { continue }
            guard let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                           width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if abs(r.minX - target.minX) < 6, abs(r.minY - target.minY) < 6,
               abs(r.width - target.width) < 6, abs(r.height - target.height) < 6 {
                return true
            }
        }
        return false
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private func isWindowAlive(_ window: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success
    }

    private func displayID(for window: AXUIElement) -> CGDirectDisplayID? {
        // AX position/size are in CG coords (top-left origin, main display at 0,0) — same as CGDisplayBounds.
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        let rect = CGRect(origin: pos, size: size)

        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let result = CGGetDisplaysWithRect(rect, 16, &displays, &count)
        if result == .success && count > 0 {
            return displays[0]
        }
        return nil
    }
}
