import SwiftUI
import AVFoundation

/// The lock screen, in Lightweight UI's dark theme: the kit's canvas with the two cards (no
/// date or time, at the user's request), and swipe up to open.
struct LockScreenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var drag: CGFloat = 0
    /// True only while a finger is down. If the system cancels the swipe (a call, Control
    /// Center, backgrounding) `onEnded` never runs; this resets anyway, so the lock screen
    /// springs back instead of staying half-way up.
    @GestureState private var swiping = false
    @FocusState private var linkFocused: Bool
    /// Follows `model.editingLink`, animated: the blur behind the Edit Link sheet.
    @State private var editBlur = false
    /// The same blur behind the how-to guide.
    @State private var guideBlur = false
    /// The link the editor sheet shows (kept while the sheet animates away).
    @State private var editorLink: SavedLink?

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let m = LockMetrics(size: geo.size, safe: model.device.safeArea) // published: follows the real inset once known
            ZStack(alignment: .top) {
              ZStack(alignment: .top) {
                LWCanvas()

            }
            .frame(width: geo.size.width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { linkFocused = false } // tap the wallpaper to put the keyboard away
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($swiping) { _, s, _ in s = true }
                    .onChanged { drag = $0.translation.height }
                    .onEnded { value in
                        debugLog("lock drag ended \(value.translation.height) predicted \(value.predictedEndTranslation.height)")
                        let flung = value.predictedEndTranslation.height < -height * 0.45
                        if value.translation.height < -120 || (value.translation.height < -30 && flung) {
                            // Hand the finger's position to the reveal: the lock keeps moving up
                            // from where it is, on the same spring as the prototype growing in.
                            withAnimation(AppModel.revealSpring) { drag = 0 }
                            model.unlock()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                        }
                    }
            )

                // Lock-screen widget, below the clock like iOS widgets. Kept outside the
                // swipe / press-and-hold gestures above so editing the link never triggers them.
                VStack(spacing: m.gap) {
                    LinkWidget(focused: $linkFocused)
                    // Saved links hug their rows, then fill the space below and scroll inside
                    // the card once they no longer fit (measured, so it holds on every screen).
                    LinkDirectoryWidget(directory: model.directory)
                    // Links pushed from the web page.
                    PushWidget(hub: model.push)
                    Spacer(minLength: 0)
                    // How to use the app: a quiet pill at the foot of the screen.
                    Button {
                        linkFocused = false
                        UISelectionFeedbackGenerator().selectionChanged()
                        model.guideOpen = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "info.circle").font(.system(size: 13, weight: .semibold))
                            Text("Quick tour").font(LW.ui)
                        }
                        .foregroundStyle(LW.ink.opacity(0.9))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(LW.card))
                        .overlay(Capsule().strokeBorder(LW.line, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(LWPress())
                    .accessibilityLabel("Quick tour of Vercel Sim")
                }
                .padding(.horizontal, m.margin)
                .padding(.top, m.clockTop)        // no clock: the cards start just under the status bar
                .padding(.bottom, m.bottom)
                .frame(width: geo.size.width, height: height)
              }
              // Editing a saved link: blur everything behind its sheet heavily (the sheet
              // itself is a separate presentation, so it stays sharp), easing in with it.
              .offset(y: min(0, drag))
              .opacity(1 + Double(min(0, drag) / (height * 1.4)))
        }
        // Editing a saved link: a heavy blur over the whole lock screen. The sheet is its own
        // presentation above this, so it stays sharp.
        .onChange(of: swiping) { _, down in
            guard !down, drag != 0 else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
        }
        .overlay { BackdropBlur(active: editBlur || guideBlur).allowsHitTesting(false) }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        // Floating sheets, above the blurred layer so they stay sharp. The editor keeps the
        // link it opened with, so its content stays put while it slides away.
        .lwFloatingSheet(isPresented: Binding(get: { model.editingLink != nil }, set: { if !$0 { model.editingLink = nil } }),
                         height: 372, scrim: 0.2) {
            if let link = editorLink {
                LinkEditor(link: link) { name, url in model.directory.update(link, name: name, url: url) }
                    .id(link.id)
            }
        }
        .onChange(of: model.editingLink) { _, link in
            if let link { editorLink = link }
            debugLog("edit sheet \(link != nil ? "up" : "down"): blur")
            editBlur = link != nil
        }
        // The guide: from ⓘ, and once on the very first launch.
        .lwFloatingSheet(isPresented: $model.guideOpen, height: 452, scrim: 0.2) { FirstRunGuide() }
        .onChange(of: model.guideOpen) { _, on in guideBlur = on }
        .onAppear {
            guard !UserDefaults.standard.bool(forKey: FirstRunGuide.seenKey), model.lockVisible else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if model.lockVisible, !model.opening, model.currentURL == nil, model.editingLink == nil, !model.panelOpen { model.guideOpen = true }
            }
        }
    }
}

/// "Open a prototype" widget: a clear link field, Paste, and Submit.
private struct LinkWidget: View {
    @EnvironmentObject private var model: AppModel
    var focused: FocusState<Bool>.Binding
    @State private var link = ""
    @State private var invalid = false
    @State private var shake: CGFloat = 0

    private var canSubmit: Bool { !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Open a prototype").font(LW.title).foregroundStyle(LW.ink)
                Spacer()
                if let failure = model.openFailure {
                    Text(failure).font(LW.caption).foregroundStyle(LW.danger).lineLimit(1).transition(.opacity)
                } else if invalid {
                    Text("Not a valid link").font(LW.caption).foregroundStyle(LW.danger).transition(.opacity)
                }
            }

            // The kit's input: 12 px corners, quiet border, ink on focus, danger when invalid;
            // the submit button is a solid ink icon button inset at the end.
            HStack(spacing: 4) {
                TextField("", text: $link, prompt: Text("Paste a Vercel link").foregroundStyle(LW.muted))
                    .font(LW.body)
                    .foregroundStyle(LW.ink)
                    .tint(LW.ink)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused(focused)
                    .onSubmit(submit)
                    .onChange(of: link) { withAnimation(LW.easeOut) { invalid = false } }
                if !link.isEmpty {
                    LWIconButton(symbol: "xmark", look: .ghost, size: 28) { link = "" }
                        .accessibilityLabel("Clear")
                }
                LWIconButton(symbol: "arrow.right", look: .solid, size: 36, busy: model.opening, action: submit)
                    .disabled(!canSubmit || model.opening)
                    .accessibilityLabel(model.opening ? "Opening prototype" : "Open prototype")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .lwField(focused: focused.wrappedValue, invalid: invalid)
        }
        .padding(16)
        .lwSurface(radius: LW.R.sheet)
        .modifier(WidgetShake(animatableData: shake))
        .onChange(of: model.lockVisible) { _, visible in
            // Clear the field only once it has left the screen, so nothing changes mid-motion.
            guard !visible else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if !model.lockVisible { link = "" } }
        }
        .onChange(of: model.openFailure) { _, failure in if failure != nil { rejected() } }
    }

    private func submit() {
        guard canSubmit, !model.opening else { return }
        guard AppModel.normalize(link) != nil else { rejected(); return }
        // Keyboard first, and open only once it has fully gone: a reveal that overlaps the
        // keyboard's dismissal can leave the lock screen drawn in place.
        let target = link
        let keyboardUp = focused.wrappedValue
        focused.wrappedValue = false
        KeyboardWait.afterHidden(keyboardUp) { if !model.open(target) { rejected() } }
    }

    private func rejected() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation(LW.easeOut) { invalid = true }
        withAnimation(.linear(duration: 0.4)) { shake += 1 }
    }
}

/// Runs `work` once the keyboard has finished hiding (or right away if it wasn't up),
/// with a short fallback in case the notification never comes.
enum KeyboardWait {
    static func afterHidden(_ wasUp: Bool, _ work: @escaping () -> Void) {
        guard wasUp else { DispatchQueue.main.async(execute: work); return }
        var done = false
        var token: NSObjectProtocol?
        let fire = {
            guard !done else { return }
            done = true
            if let token { NotificationCenter.default.removeObserver(token) }
            work()
        }
        token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in fire() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fire() }
    }
}

private struct WidgetShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// The kit's canvas: paper (`bg`) with a faint dot grid, as on the kit's own landing page.
private struct LWCanvas: View {
    var body: some View {
        LW.bg
            .overlay {
                Canvas { ctx, size in
                    let step: CGFloat = 22, r: CGFloat = 1
                    var y = step / 2
                    while y < size.height {
                        var x = step / 2
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(LW.wash(6)))
                            x += step
                        }
                        y += step
                    }
                }
            }
            .allowsHitTesting(false)
    }
}

private struct QuickAction: View {
    let symbol: String
    let on: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(on ? .black : .white)
            .frame(width: 50, height: 50)
            .background {
                Circle().fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial))
            }
            .environment(\.colorScheme, .dark)
            .scaleEffect(pressed ? 1.18 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .contentShape(Circle().inset(by: -10)) // larger touch target, same look
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressed = $0 }) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                action()
            }
    }
}

/// Lock-screen strings: "Friday, October 2" (as in the Figma frame and the Mac app) and
/// "1:43" — no AM/PM and no leading zero in 12-hour time; "01:43"-style when the iPhone
/// is set to 24-hour time, like the real lock screen.
enum LockClock {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
    static var uses24Hour: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("H")
    }
    static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
    static func time(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let hour = uses24Hour ? String(format: "%02d", h) : String(h % 12 == 0 ? 12 : h % 12)
        return "\(hour):\(String(format: "%02d", m))"
    }
}

/// The real torch on a device; a no-op in the Simulator.
enum Torch {
    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

/// Lock-screen layout for the current screen, from the Figma frame (iPhone 13 mini, 375 × 812).
/// Bigger phones scale the clock and spacing with the screen width, so the composition keeps
/// its proportions; the cards span the width with proportional margins (no fixed cap), and
/// the text inside them stays at its point size, so taller screens simply show more links.
struct LockMetrics {
    /// Width relative to the 375 pt design (1.0 on mini … ≈1.17 on Pro Max).
    let k: CGFloat
    let clockTop: CGFloat
    let widgetsTop: CGFloat
    let margin: CGFloat
    let gap: CGFloat
    let bottom: CGFloat

    init(size: CGSize, safe: UIEdgeInsets) {
        k = min(max(size.width / 375, 0.85), 1.25) // 320 pt (Display Zoom) … 440 pt (Pro Max)
        // Figma: the date starts 64.535 pt down, 14.5 pt under the mini's 50 pt status bar.
        // Dynamic Island phones have a taller top inset; keep the same clearance under it.
        clockTop = max(64.535, safe.top + 14.535)
        // Figma: the first widget starts 204 pt down, 139.5 pt under the date's top edge.
        widgetsTop = clockTop + 139.465 * k
        margin = (22 * k).rounded()
        gap = (12 * k).rounded()
        bottom = max(safe.bottom, 12) + 14  // clear of the home indicator
    }
}

/// Key-window safe area. A GeometryReader under .ignoresSafeArea() reports zero insets.
enum DeviceSafeArea {
    static var insets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }
}

/// A strong blur that eases in and out by animating the blur effect itself (UIKit grows the
/// radius from nothing), rather than fading a fixed blur. SwiftUI's `.blur` doesn't render
/// over this lock screen while a sheet is up.
struct BackdropBlur: UIViewRepresentable {
    var active: Bool
    func makeUIView(context: Context) -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: nil)
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: UIVisualEffectView, context: Context) {
        let target: UIVisualEffect? = active ? UIBlurEffect(style: .systemThinMaterial) : nil   // follows light / dark
        guard (v.effect == nil) != (target == nil) else { return }
        UIViewPropertyAnimator(duration: active ? 0.45 : 0.32, dampingRatio: 1) { v.effect = target }.startAnimation()
    }
}
