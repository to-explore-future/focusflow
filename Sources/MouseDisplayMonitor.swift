import Cocoa

final class MouseDisplayMonitor {
    private var timer: Timer?
    private var eventMonitor: Any?
    private var lastDisplayID: CGDirectDisplayID = 0
    private var wasButtonDown: Bool = false
    private var lastCheck: TimeInterval = 0
    private let onCross: (CGDirectDisplayID) -> Void
    private let onDragRelease: (CGDirectDisplayID) -> Void

    init(onCross: @escaping (CGDirectDisplayID) -> Void,
         onDragRelease: @escaping (CGDirectDisplayID) -> Void) {
        self.onCross = onCross
        self.onDragRelease = onDragRelease
    }

    func start() {
        lastDisplayID = currentMouseDisplayID() ?? 0

        // 事件驱动：鼠标不动时收不到任何事件（零唤醒），一动就来回调。
        // 这比每 50ms 轮询省电，响应也比 50ms 更及时。
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseUp, .rightMouseUp,
        ]
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.evaluate(throttled: true)
        }

        // 没有辅助功能权限时拿不到全局事件（监听对象照样能创建成功，但永远不回调），
        // 所以用 AXIsProcessTrusted 判断，而不是判断 eventMonitor 是否为 nil。
        if !AXIsProcessTrusted() || eventMonitor == nil {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.evaluate(throttled: false)
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        timer?.invalidate()
        timer = nil
    }

    /// 鼠标快速移动时事件很密，20ms 内只判断一次，避免无谓的显示器查询。
    private func evaluate(throttled: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if throttled && now - lastCheck < 0.02 { return }
        lastCheck = now

        let buttonDown = NSEvent.pressedMouseButtons != 0
        let justReleased = wasButtonDown && !buttonDown
        wasButtonDown = buttonDown

        // Don't fire cross events while any mouse button is held — the user is dragging
        // a window or selecting across displays, and an activation would steal focus and
        // interrupt the drag.
        if buttonDown { return }

        guard let id = currentMouseDisplayID() else { return }

        if justReleased {
            // The user just released a drag. Whatever window they dropped becomes the new
            // entry for this display, and we deliberately skip the cross-activation that
            // would otherwise reactivate the previous frontmost on this display and steal
            // focus from the dropped window.
            onDragRelease(id)
            lastDisplayID = id
            return
        }

        if id != lastDisplayID && lastDisplayID != 0 {
            lastDisplayID = id
            onCross(id)
        } else {
            lastDisplayID = id
        }
    }

    private func currentMouseDisplayID() -> CGDirectDisplayID? {
        // Use CG coords (top-left origin) so cursor and window display lookups share
        // the same CGDirectDisplayID namespace as CGGetDisplaysWithRect — important on
        // setups with USB / DisplayLink monitors where NSScreen mapping can drift.
        guard let cgLoc = CGEvent(source: nil)?.location else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(cgLoc, 16, &displays, &count)
        return (result == .success && count > 0) ? displays[0] : nil
    }
}
