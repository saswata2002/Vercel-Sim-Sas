import UIKit
import WebKit

/// Plays real iOS haptics for whatever a prototype asks for. Prototypes reach it three ways
/// (see `Scripts.haptics`):
///  1. `webkit.messageHandlers.haptic.postMessage(kind | {type, intensity})`, the hook
///     prototypes built for a native shell use (noon-home's `Haptics` posts 'tick' / 'snap' / 'tap').
///  2. `navigator.vibrate(ms | pattern)`: WebKit on iOS has no Vibration API, so the app
///     provides one and maps durations to Taptic Engine pulses.
///  3. toggling an `<input type="checkbox" switch>`, the iOS-Safari haptic trick.
/// When one moment arrives through two of these (a prototype that both posts a named haptic
/// and calls vibrate), only the first plays, so it never feels like a double bump.
@MainActor
final class HapticEngine {
    static let shared = HapticEngine()
    var enabled = true
    /// True while the lock screen is up (the page may be loading behind it).
    var suppressed = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    private var lastAt: CFTimeInterval = 0
    private var pending: [DispatchWorkItem] = []

    enum Pulse: Equatable, CustomStringConvertible {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle, CGFloat)
        case selection
        case notify(UINotificationFeedbackGenerator.FeedbackType)

        var description: String {
            switch self {
            case .selection: return "selection"
            case .impact(let s, let i):
                let name = [UIImpactFeedbackGenerator.FeedbackStyle.light: "light", .medium: "medium", .heavy: "heavy", .soft: "soft", .rigid: "rigid"][s] ?? "impact"
                return i < 1 ? "\(name) impact @\(String(format: "%.2f", i))" : "\(name) impact"
            case .notify(let t):
                return [UINotificationFeedbackGenerator.FeedbackType.success: "success", .warning: "warning", .error: "error"][t] ?? "notification"
            }
        }
    }

    /// Wake the Taptic Engine so the first pulse isn't late.
    func prepare() {
        [light, medium, heavy, soft, rigid].forEach { $0.prepare() }
        selection.prepare()
        notification.prepare()
    }

    // MARK: entry points

    /// A named haptic from the page: "light", "medium", "heavy", "soft", "rigid",
    /// "selection", "success", "warning", "error", plus common aliases ("tick", "snap",
    /// "tap", "impactLight", "notificationSuccess", …). Accepts `{type|style|kind, intensity}` too.
    func play(message body: Any) {
        var name = ""
        var intensity: CGFloat?
        if let s = body as? String { name = s }
        else if let n = body as? NSNumber { vibrate(pattern: [n.doubleValue]); return }
        else if let d = body as? [String: Any] {
            name = (d["type"] ?? d["style"] ?? d["kind"] ?? d["name"] ?? "") as? String ?? ""
            if let i = d["intensity"] as? NSNumber { intensity = CGFloat(truncating: i) }
            if let p = d["pattern"] as? [NSNumber] { vibrate(pattern: p.map(\.doubleValue)); return }
            if let ms = d["duration"] as? NSNumber, name.isEmpty { vibrate(pattern: [ms.doubleValue]); return }
        }
        guard let pulse = Self.pulse(named: name, intensity: intensity) else {
            debugLog("haptic: unknown kind '\(name)', playing light")
            fire(.impact(.light, intensity ?? 1), source: name)
            return
        }
        fire(pulse, source: name)
    }

    /// `navigator.vibrate(pattern)`: [on, off, on, …] in ms; `0` / `[]` cancels.
    func vibrate(pattern: [Double]) {
        pending.forEach { $0.cancel() }
        pending.removeAll()
        guard pattern.contains(where: { $0 > 0 }) else { return }
        let ons = stride(from: 0, to: pattern.count, by: 2).map { pattern[$0] }.filter { $0 > 0 }
        // Two short pulses close together ([10, 40, 16]) is how web code spells "success";
        // played literally they'd blur into one, so use the system's success haptic.
        if ons.count == 2, pattern.count <= 3, pattern.reduce(0, +) <= 100 {
            fire(.notify(.success), source: "vibrate \(pattern)")
            return
        }
        var t: Double = 0
        for (i, v) in pattern.enumerated() {
            if i % 2 == 0, v > 0 {
                let pulse = Self.pulse(forDuration: v)
                if t == 0 { fire(pulse, source: "vibrate \(Int(v))ms") }
                else {
                    let work = DispatchWorkItem { [weak self] in self?.fire(pulse, source: "vibrate \(Int(v))ms", dedupe: false) }
                    pending.append(work)
                    DispatchQueue.main.asyncAfter(deadline: .now() + t / 1000, execute: work)
                }
            }
            t += v
        }
    }

    // MARK: playing

    private func fire(_ pulse: Pulse, source: String, dedupe: Bool = true) {
        guard enabled, !suppressed else { return }
        let now = CACurrentMediaTime()
        if dedupe, now - lastAt < 0.035 { return } // same moment, second channel
        lastAt = now
        switch pulse {
        case .impact(let style, let i):
            let g: UIImpactFeedbackGenerator = [.light: light, .medium: medium, .heavy: heavy, .soft: soft, .rigid: rigid][style] ?? light
            g.impactOccurred(intensity: max(0, min(1, i)))
            g.prepare()
        case .selection:
            selection.selectionChanged()
            selection.prepare()
        case .notify(let type):
            notification.notificationOccurred(type)
            notification.prepare()
        }
        debugLog("haptic: \(pulse) ← \(source)")
    }

    // MARK: mapping

    static func pulse(named raw: String, intensity: CGFloat?) -> Pulse? {
        let k = raw.lowercased().replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        let i = intensity ?? 1
        switch k {
        case "selection", "selectionchanged", "select", "tick", "change", "changed": return .selection
        case "light", "impactlight", "tap", "click", "lightimpact": return .impact(.light, i)
        case "medium", "impactmedium", "impact", "snap", "bump", "mediumimpact": return .impact(.medium, i)
        case "heavy", "impactheavy", "thud", "heavyimpact", "long": return .impact(.heavy, i)
        case "soft", "impactsoft": return .impact(.soft, i)
        case "rigid", "impactrigid", "hard": return .impact(.rigid, i)
        case "success", "notificationsuccess", "done", "confirm": return .notify(.success)
        case "warning", "notificationwarning", "warn": return .notify(.warning)
        case "error", "notificationerror", "fail", "failure": return .notify(.error)
        default: return nil
        }
    }

    /// Vibration durations → the closest Taptic Engine pulse.
    static func pulse(forDuration ms: Double) -> Pulse {
        switch ms {
        case ..<7: return .selection                     // 1–6 ms: a tick
        case ..<13: return .impact(.light, 1)            // 7–12 ms: a tap
        case ..<25: return .impact(.medium, 1)           // 13–24 ms
        case ..<60: return .impact(.heavy, 1)            // 25–59 ms
        default: return .impact(.heavy, 1)               // longer buzzes: the strongest pulse
        }
    }
}

/// Script-message bridge. WKUserContentController retains its handlers, so this holds the
/// engine, not the model, to avoid a retain cycle.
final class HapticMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body, name = message.name
        Task { @MainActor in
            switch name {
            case "__vsVibrate":
                let pattern = (body as? [NSNumber])?.map(\.doubleValue) ?? (body as? NSNumber).map { [$0.doubleValue] } ?? []
                HapticEngine.shared.vibrate(pattern: pattern)
            case "__vsSwitch":
                HapticEngine.shared.play(message: "selection")
            default:
                HapticEngine.shared.play(message: body)
            }
        }
    }

    /// Handler names prototypes post to ("haptic" is what noon-home uses).
    static let publicNames = ["haptic", "haptics", "hapticFeedback", "vibrate"]
    static let internalNames = ["__vsVibrate", "__vsSwitch"]
}

/// The page's "first complete screen is painted" signal (Scripts.readySignal).
final class ReadyMessageHandler: NSObject, WKScriptMessageHandler {
    weak var model: AppModel?
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let why = (message.body as? [String: Any])?["why"] as? String ?? "ready"
        let href = (message.body as? [String: Any])?["href"] as? String ?? ""
        guard !href.hasPrefix("about:") else { return }
        Task { @MainActor in self.model?.pageBecameReady(why) }
    }
}
