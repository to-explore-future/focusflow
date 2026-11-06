import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mouseMonitor: MouseDisplayMonitor!
    private var focusTracker: FocusTracker!
    private var enabled = true

    private var enabledItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private let launchAgentLabel = "com.local.autofocusmonitor"
    private let logPath = "/tmp/autofocusmonitor.log"

    private func log(_ s: String) {
        let line = "[\(Date())] \(s)\n"
        if let data = line.data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: logPath) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        observeScreenChanges()
        log("launched. AX trusted at start: \(AXIsProcessTrusted()) lang=\(L10n.currentCode)")

        if !ensureAccessibilityPermission() {
            log("not trusted; polling for grant")
            let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.log("trust acquired via polling")
                    self?.startCore()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            return
        }

        startCore()
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    private func startCore() {
        guard focusTracker == nil else { return }
        focusTracker = FocusTracker()
        focusTracker.start()

        mouseMonitor = MouseDisplayMonitor(
            onCross: { [weak self] newDisplayID in
                guard let self = self, self.enabled else { return }
                self.focusTracker.activateLastWindow(on: newDisplayID)
                self.updateStatusIcon()
            },
            onDragRelease: { [weak self] displayID in
                guard let self = self, self.enabled else { return }
                self.focusTracker.recordDroppedWindow(on: displayID)
            }
        )
        mouseMonitor.start()
    }

    // MARK: - 辅助功能权限

    private func ensureAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: NSDictionary = [key: true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    @objc private func requestAccessibility(_ sender: NSMenuItem) {
        _ = ensureAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        if AXIsProcessTrusted() {
            startCore()
        }
    }

    // MARK: - 开机自启

    private var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    private var isLoginItemEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if isLoginItemEnabled {
                removeLaunchAgent()
            } else {
                try installLaunchAgent()
            }
        } catch {
            log("login item change failed: \(error)")
        }
        sender.state = isLoginItemEnabled ? .on : .off
    }

    private func installLaunchAgent() throws {
        let exe = Bundle.main.executablePath
            ?? "/Applications/FocusFlow.app/Contents/MacOS/FocusFlow"
        let dir = (launchAgentPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: launchAgentPath))

        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(launchAgentLabel)"])
        if runLaunchctl(["bootstrap", "gui/\(uid)", launchAgentPath]) != 0 {
            _ = runLaunchctl(["load", "-w", launchAgentPath])
        }
    }

    private func removeLaunchAgent() {
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(launchAgentLabel)"])
        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }

    @discardableResult
    private func runLaunchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            log("launchctl \(args) failed: \(error)")
            return -1
        }
    }

    // MARK: - 菜单

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        L10n.currentCode = code
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        enabledItem = NSMenuItem(title: L10n.t("enabled"), action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = enabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        permissionItem = NSMenuItem(title: L10n.t("accessibility"),
                                    action: #selector(requestAccessibility(_:)), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        loginItem = NSMenuItem(title: L10n.t("launchAtLogin"),
                               action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled ? .on : .off
        menu.addItem(loginItem)

        // 语言
        let langItem = NSMenuItem(title: L10n.t("language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in L10n.languages {
            let item = NSMenuItem(title: lang.name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = (lang.code == L10n.currentCode) ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        let donateItem = NSMenuItem(title: L10n.t("donate"),
                                    action: #selector(showDonate(_:)), keyEquivalent: "")
        donateItem.target = self
        menu.addItem(donateItem)

        menu.addItem(NSMenuItem.separator())
        let buildItem = NSMenuItem(title: "\(L10n.t("version"))：\(Self.buildStamp)",
                                   action: nil, keyEquivalent: "")
        buildItem.isEnabled = false
        menu.addItem(buildItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.t("quit"), action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.toolTip = L10n.t("tooltip")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
        updateStatusIcon()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        permissionItem.title = trusted
            ? "\(L10n.t("accessibility"))：\(L10n.t("granted"))"
            : "\(L10n.t("accessibility"))：\(L10n.t("notGranted"))"
        permissionItem.state = trusted ? .on : .off
        loginItem.state = isLoginItemEnabled ? .on : .off
        enabledItem.state = enabled ? .on : .off
    }

    // MARK: - 赞助

    private var donateWindow: NSWindow?

    @objc private func showDonate(_ sender: NSMenuItem) {
        if let window = donateWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let width: CGFloat = 320
        let qr: CGFloat = 220
        let height: CGFloat = qr + 140

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = L10n.t("donate")
        window.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // 白底圆角卡片：二维码必须有白底才扫得出来，顺便去掉原图那种"支付广告"的观感
        let card = NSView(frame: NSRect(x: (width - qr) / 2, y: 108, width: qr, height: qr))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 14
        view.addSubview(card)

        let imageView = NSImageView(frame: NSRect(x: 10, y: 10, width: qr - 20, height: qr - 20))
        imageView.image = NSImage(named: "DonateQR")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        card.addSubview(imageView)

        let line1 = NSTextField(labelWithString: L10n.t("donateLine1"))
        line1.font = NSFont.boldSystemFont(ofSize: 13)
        line1.alignment = .center
        line1.frame = NSRect(x: 16, y: 78, width: width - 32, height: 18)
        view.addSubview(line1)

        let line2 = NSTextField(labelWithString: L10n.t("donateLine2"))
        line2.font = NSFont.systemFont(ofSize: 11)
        line2.textColor = .secondaryLabelColor
        line2.alignment = .center
        line2.lineBreakMode = .byWordWrapping
        line2.maximumNumberOfLines = 2
        line2.frame = NSRect(x: 16, y: 52, width: width - 32, height: 24)
        view.addSubview(line2)

        let scan = NSTextField(labelWithString: L10n.t("donateScan"))
        scan.font = NSFont.systemFont(ofSize: 10)
        scan.textColor = .tertiaryLabelColor
        scan.alignment = .center
        scan.frame = NSRect(x: 16, y: 34, width: width - 32, height: 14)
        view.addSubview(scan)

        window.contentView = view
        window.center()
        donateWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 菜单栏图标

    private func activeScreenIndex() -> Int {
        guard let loc = CGEvent(source: nil)?.location else { return 0 }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let ok = CGGetDisplaysWithPoint(loc, 16, &ids, &count)
        let activeID: CGDirectDisplayID = (ok == .success && count > 0) ? ids[0] : 0
        for (i, screen) in NSScreen.screens.enumerated() {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               num.uint32Value == activeID {
                return i
            }
        }
        return 0
    }

    private func updateStatusIcon() {
        let frames = NSScreen.screens.map { $0.frame }
        statusItem?.button?.image = statusImage(frames: frames, active: activeScreenIndex())
        statusItem?.button?.title = ""
    }

    /// 按屏幕在系统里的真实排列画图标：位置、大小都按比例缩到 22×22 里。
    /// 有焦点的那块：蓝色实心 + 白色鼠标指针；其余：灰色空心框。
    private func statusImage(frames: [NSRect], active: Int) -> NSImage {
        let size = NSSize(width: 32, height: 22)
        let accent = NSColor(srgbRed: 0.29, green: 0.56, blue: 1.0, alpha: 1.0)
        let inactive = NSColor(srgbRed: 0.66, green: 0.66, blue: 0.68, alpha: 1.0)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let first = frames.first else { return true }

            var union = first
            for f in frames.dropFirst() { union = union.union(f) }
            if union.width <= 0 || union.height <= 0 { return true }

            let padX: CGFloat = 1.5
            let padY: CGFloat = 2
            let availW = size.width - padX * 2
            let availH = size.height - padY * 2
            let scale = min(availW / union.width, availH / union.height)
            let ox = padX + (availW - union.width * scale) / 2 - union.minX * scale
            let oy = padY + (availH - union.height * scale) / 2 - union.minY * scale

            var activeRect: NSRect?

            for (index, frame) in frames.enumerated() {
                var rect = NSRect(x: frame.minX * scale + ox,
                                  y: frame.minY * scale + oy,
                                  width: frame.width * scale,
                                  height: frame.height * scale)
                rect = rect.insetBy(dx: 0.4, dy: 0.4)

                let minSide: CGFloat = 3.2
                if rect.width < minSide {
                    rect.origin.x -= (minSide - rect.width) / 2
                    rect.size.width = minSide
                }
                if rect.height < minSide {
                    rect.origin.y -= (minSide - rect.height) / 2
                    rect.size.height = minSide
                }

                let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                if index == active {
                    accent.setFill()
                    path.fill()
                    activeRect = rect
                } else {
                    inactive.setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }

            if let rect = activeRect {
                self.drawCursor(in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// 在有焦点的那块屏里画一个白色小鼠标
    private func drawCursor(in rect: NSRect) {
        let h = min(rect.height * 0.88, rect.width * 0.52, 8.0)
        let originX = rect.midX - h * 0.31
        // y 轴向上：tip 在上方、身体朝下，才是左上指向的箭头
        let originY = rect.midY + h * 0.46
        let shape: [(CGFloat, CGFloat)] = [
            (0.00, 0.00), (0.00, 0.78), (0.20, 0.60), (0.33, 0.98),
            (0.47, 0.93), (0.35, 0.56), (0.62, 0.54),
        ]
        let path = NSBezierPath()
        for (i, p) in shape.enumerated() {
            let pt = NSPoint(x: originX + p.0 * h, y: originY - p.1 * h)
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.close()
        NSColor.white.setFill()
        path.fill()
        NSColor(srgbRed: 0.10, green: 0.16, blue: 0.32, alpha: 0.9).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    private static let buildStamp: String = {
        guard let path = Bundle.main.executablePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return "unknown" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }()

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        sender.state = enabled ? .on : .off
    }
}
