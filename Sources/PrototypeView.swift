import SwiftUI
import WebKit

/// The prototype, full-bleed. The WKWebView lives in AppModel so it survives the lock
/// screen; touches, scrolling and animations are WebKit's own, exactly as in Safari.
struct PrototypeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            WebViewHost(webView: model.webView) { model.panelOpen = true }
            // Hairline progress at the very top while a page loads.
            if model.isLoading, model.progress < 1 {
                GeometryReader { geo in
                    Capsule()
                        .fill(LW.ink)
                        .frame(width: geo.size.width * max(0.08, model.progress), height: 2.5)
                        .animation(.easeOut(duration: 0.25), value: model.progress)
                }
                .frame(height: 2.5)
                .transition(.opacity)
            }
        }
    }
}

private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    let onTwoFingerHold: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTwoFingerHold) }

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        // The options sheet opens on a two-finger double-tap (installed on the window, see
        // TwoFingerDoubleTap). Two-finger press-and-hold does the same; neither ever takes a
        // single-finger touch from the prototype.
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.numberOfTouchesRequired = 2
        hold.minimumPressDuration = 0.5
        hold.cancelsTouchesInView = false
        hold.delegate = context.coordinator
        webView.addGestureRecognizer(hold)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onHold: () -> Void
        init(_ onHold: @escaping () -> Void) { self.onHold = onHold }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onHold()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

struct LoadErrorView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        // The kit's end screen: icon tile, a Geist Pixel title, muted body, one primary action.
        VStack(spacing: 0) {
            LWIconTile(symbol: "wifi.exclamationmark", size: 48).padding(.bottom, 18)
            Text("Can\u{2019}t open this page").font(LW.pixel(28)).foregroundStyle(LW.ink).multilineTextAlignment(.center)
            Text(message).font(LW.body).foregroundStyle(LW.muted).multilineTextAlignment(.center)
                .padding(.top, 8).frame(maxWidth: 300)
            HStack(spacing: 10) {
                Button("Home") { model.goHome() }.buttonStyle(LWButton(variant: .secondary, radius: LW.R.x2l, height: 48))
                Button("Try again") { model.reload() }.buttonStyle(LWButton(variant: .primary, radius: LW.R.x2l, height: 48))
            }
            .padding(.top, 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LW.bg)
        .ignoresSafeArea()
    }
}

/// Optional on-screen iteration selector (off by default — the control panel always has it).
struct IterationPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let switcher = model.switcher {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    ForEach(switcher.items) { item in
                        if item.index == switcher.items.first(where: { !$0.isOption })?.index { Divider().frame(width: 18).padding(.vertical, 1) }
                        Button { model.press(item) } label: {
                            Group {
                                if item.isOption { Text(item.text).font(LW.sans(15, .semibold)).monospacedDigit() }
                                else { Image(systemName: item.symbol).font(.system(size: 14, weight: .medium)) }
                            }
                            .frame(width: 34, height: 34)
                            .foregroundStyle(item.selected ? LW.onInk : LW.ink)
                            .background(RoundedRectangle(cornerRadius: LW.R.chip, style: .continuous).fill(item.selected ? LW.ink : LW.wash(4)))
                            .contentShape(Rectangle().inset(by: -5))
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .padding(5)
                .lwSurface(radius: LW.R.control + 2)
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)   // the kit's "pill" lift
                .padding(.trailing, 6)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)          // Lightweight UI: 97% while held
            .animation(LW.easeOut(160), value: configuration.isPressed)
    }
}
