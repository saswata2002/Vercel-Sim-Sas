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
                        .fill(Color.accentColor)
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
        VStack(spacing: 10) {
            Text("Can’t open this page").font(.title2.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button("Try again") { model.reload() }
                Button("Home") { model.goHome() }
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
                                if item.isOption { Text(item.text).font(.system(size: 15, weight: .semibold)).monospacedDigit() }
                                else { Image(systemName: item.symbol).font(.system(size: 14, weight: .semibold)) }
                            }
                            .frame(width: 34, height: 34)
                            .foregroundStyle(item.selected ? .white : .primary)
                            .background(Circle().fill(item.selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial)))
                            .contentShape(Circle().inset(by: -5))
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .padding(5)
                .background(Capsule().fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(.trailing, 6)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
