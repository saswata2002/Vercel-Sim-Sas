import SwiftUI

// Vercel Sim — the iPhone companion to the Mac "Vercel Mac Sim": open a Vercel
// prototype full-screen on a real (or simulated) iPhone, with the same lock screen,
// 375-pt base scaling and lifted-out iteration selector.

@main
struct VercelSimApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let revealed = !model.lockVisible
            let _ = model.renderNudge // re-render on a watchdog nudge
            ZStack {
                Color.black

                // The prototype grows into place as the lock screen leaves, like an app
                // opening: 94% → 100%, faded in, rounded corners → square. Until its first
                // complete screen is painted, a plain backdrop stands in for it.
                ZStack {
                    Color(uiColor: .systemBackground)
                    PrototypeView()
                        .opacity(model.contentShown ? 1 : 0.001)
                    if let launch = model.launchImage {
                        // Its saved first screen, until the live page takes over underneath.
                        Image(uiImage: launch)
                            .resizable()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .opacity(model.launchFading ? 0 : 1)
                            .allowsHitTesting(false)
                    } else if revealed && !model.contentShown && model.currentURL != nil {
                        LaunchSpinner()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: revealed ? 0 : DisplayCorner.radius, style: .continuous))
                .scaleEffect(revealed ? 1 : 0.94)
                .opacity(revealed ? 1 : 0.001) // not 0: WebKit keeps painting the page underneath
                .allowsHitTesting(revealed)     // …but it mustn't take the lock screen's touches

                if model.pillVisible, model.switcher != nil, revealed, model.contentShown {
                    IterationPill()
                        .transition(.opacity)
                }

                if let error = model.loadError, revealed {
                    LoadErrorView(message: error)
                }

                // Always mounted; slides fully off the top (past the safe area) when revealed.
                // Slides fully off the top (past the safe area) when revealed, then leaves the
                // hierarchy once the motion is over, so it can never linger on screen.
                if model.lockMounted {
                    LockScreenView()
                        .offset(y: revealed ? -(geo.size.height + 60) : 0)
                        .allowsHitTesting(model.lockVisible)
                        .zIndex(10)
                }
            }
            .onChange(of: revealed) { _, r in
                if r { model.revealAck = true }
                debugLog("root: revealed \(r)")
            }
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        // Over a prototype the system chrome is opt-in; the lock screen always shows it.
        .statusBarHidden(!model.lockVisible && !model.showStatusBar)
        .persistentSystemOverlays(!model.lockVisible && !model.showHomeIndicator ? .hidden : .automatic)
        .preferredColorScheme(model.lockVisible ? .dark : model.appearance.colorScheme)
        .sheet(isPresented: $model.panelOpen) {
            ControlPanel()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear { model.refreshDevice() }
        // Two-finger double-tap anywhere (prototype or lock screen) opens the options sheet.
        .background(TwoFingerDoubleTap { if model.editingLink == nil { model.panelOpen = true } })
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            model.panelOpen = true
        }
    }
}

/// Shown only if a page swiped open from the lock screen takes more than a moment.
private struct LaunchSpinner: View {
    @State private var visible = false
    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.easeIn(duration: 0.2)) { visible = true }
            }
    }
}

/// The display's own corner radius (points) per iPhone 12–17 screen class, so the reveal
/// starts from the physical screen's shape.
enum DisplayCorner {
    static var radius: CGFloat {
        let b = UIScreen.main.bounds
        switch (Int(min(b.width, b.height)), Int(max(b.width, b.height))) {
        case (375, 812): return 44      // 12 mini, 13 mini
        case (390, 844): return 47.33   // 12, 12 Pro, 13, 13 Pro, 14, 16e, 17e
        case (428, 926): return 53.33   // 12/13 Pro Max, 14 Plus
        case (393, 852), (430, 932): return 55  // 14 Pro…16 / Plus / Pro Max
        case (402, 874), (440, 956), (420, 912): return 62  // 16 Pro/Pro Max, 17 series, Air
        default: return 44
        }
    }
}

/// Installs a two-finger double-tap recogniser on the window, so it works over everything
/// (the web view, the lock screen and its widgets) without taking touches from any of them.
/// A single finger never triggers it: one-finger double-taps belong to the prototype.
private struct TwoFingerDoubleTap: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Installer {
        let v = Installer()
        v.coordinator = context.coordinator
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: Installer, context: Context) { context.coordinator.action = action }

    final class Installer: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let coordinator, coordinator.recognizer.view !== window else { return }
            window.addGestureRecognizer(coordinator.recognizer)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void = {}
        lazy var recognizer: UITapGestureRecognizer = {
            let g = UITapGestureRecognizer(target: self, action: #selector(fire(_:)))
            g.numberOfTouchesRequired = 2
            g.numberOfTapsRequired = 2
            g.cancelsTouchesInView = false   // the page still gets every touch
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
            g.delegate = self
            return g
        }()
        @objc func fire(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            debugLog("two-finger double-tap → options")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// Shake to open the control panel (Simulator: Device ▸ Shake, ⌃⌘Z).
extension Notification.Name {
    static let deviceDidShake = Notification.Name("VercelSim.deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
