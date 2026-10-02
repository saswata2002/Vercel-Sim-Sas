import UIKit

/// The phone this app is running on, and how a 375 × 812 design is fitted to it.
///
/// The design is laid out at 375 CSS px across and scaled by `zoom` to fill the screen
/// width, so spacing and proportions stay exactly as designed. The layout height follows
/// the device's own aspect ratio (812 on a 13 mini, 815 on a 17 Pro, 667 on an SE), and
/// the device's safe areas reach the page as `env(safe-area-inset-*)`, divided by `zoom`.
struct DeviceProfile: Equatable {
    static let base = CGSize(width: 375, height: 812)

    let name: String
    let screen: CGSize        // points
    let scale: CGFloat        // @2x / @3x
    let safeArea: UIEdgeInsets
    let zoom: CGFloat         // page zoom applied to the web view
    var layout: CGSize { CGSize(width: (screen.width / zoom).rounded(), height: (screen.height / zoom).rounded()) }
    var layoutSafeArea: UIEdgeInsets {
        UIEdgeInsets(top: (safeArea.top / zoom).rounded(), left: (safeArea.left / zoom).rounded(),
                     bottom: (safeArea.bottom / zoom).rounded(), right: (safeArea.right / zoom).rounded())
    }

    static func current(fitBase: Bool) -> DeviceProfile {
        let s = UIScreen.main
        let w = min(s.bounds.width, s.bounds.height), h = max(s.bounds.width, s.bounds.height)
        return DeviceProfile(name: modelName, screen: CGSize(width: w, height: h), scale: s.scale,
                             safeArea: DeviceSafeArea.insets,
                             // Below 1 too: Display Zoom (Larger Text) makes a 12 mini / 13 / 14
                             // report 320 pt, and 375 CSS px must still fit across it.
                             zoom: fitBase ? w / base.width : 1)
    }

    /// "iPhone 17 Pro", from the Simulator's device name or the hardware identifier.
    static var modelName: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] { return sim }
        var info = utsname()
        uname(&info)
        let id = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        if let name = knownModels[id] { return name }
        // Newer hardware than this table: describe it by its screen instead.
        let b = UIScreen.main.bounds
        return "iPhone (\(Int(min(b.width, b.height))) × \(Int(max(b.width, b.height))))"
    }

    private static let knownModels: [String: String] = [
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air",
    ]

    /// Dynamic Island devices have a ≥ 59 pt top inset; notch devices 44–50 pt.
    var cutout: String {
        if safeArea.top >= 59 { return "Dynamic Island" }
        if safeArea.top >= 44 { return "Notch" }
        return "None"
    }

    /// "375 × 815 layout · ×1.07"
    var fitSummary: String {
        let size = "\(Int(layout.width)) × \(Int(layout.height)) layout"
        return zoom == 1 ? "\(size) · 1:1" : "\(size) · ×\(String(format: "%.2f", zoom))"
    }
}
