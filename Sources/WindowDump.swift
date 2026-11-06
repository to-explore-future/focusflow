import AppKit
import CoreGraphics

enum WindowDump {
    static func run() -> Int32 {
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                           width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r.width < 100 || r.height < 60 { continue }
            let name = w[kCGWindowOwnerName as String] as? String ?? "?"
            let wid = (w[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            let cx = Int(r.midX), cy = Int(r.midY)
            print("\(name)|win=\(wid)|center=\(cx),\(cy)")
        }
        return 0
    }
}
