import SwiftUI
import AVFoundation

/// iOS-style lock screen: the user's wallpaper, the live date and time in the Figma
/// typography ("📱 Lock Screen", Motion (Sas) 1526:74437), quick-action buttons and
/// swipe up to open the prototype.
struct LockScreenView: View {
    @EnvironmentObject private var model: AppModel
    @State private var drag: CGFloat = 0
    @FocusState private var linkFocused: Bool
    /// Follows `model.editingLink`, animated: the blur behind the Edit Link sheet.
    @State private var editBlur = false

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let m = LockMetrics(size: geo.size, safe: model.device.safeArea) // published: follows the real inset once known
            ZStack(alignment: .top) {
              ZStack(alignment: .top) {
                Wallpaper()

                // Date and Time — Figma: stack starts 64.535 pt from the top; the time is
                // pulled up 12.209 pt into the date's line box.
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 0) {
                        Text(LockClock.date(context.date))
                            .font(.system(size: 19.186 * m.k, weight: .medium))      // SF Pro Medium (510)
                            .tracking(-0.2267 * m.k)
                            .frame(height: 24.419 * m.k)
                            .padding(.bottom, -12.209 * m.k)
                        Text(LockClock.time(context.date))
                            .font(.system(size: 94.186 * m.k, weight: .semibold))    // SF Pro Semibold (590)
                            .tracking(-1.439 * m.k)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, m.clockTop)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { linkFocused = false } // tap the wallpaper to put the keyboard away
            .gesture(
                DragGesture(minimumDistance: 8)
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
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, m.margin)
                .padding(.top, m.widgetsTop)
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
        .overlay { BackdropBlur(active: editBlur).allowsHitTesting(false) }
        .ignoresSafeArea()
        // Presented from here, outside the blurred layer, so the sheet itself stays sharp.
        .sheet(item: $model.editingLink) { link in
            LinkEditor(link: link) { name, url in model.directory.update(link, name: name, url: url) }
        }
        .onChange(of: model.editingLink != nil) { _, on in
            debugLog("edit sheet \(on ? "up" : "down"): blur")
            editBlur = on
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Open a prototype").font(.system(size: 16, weight: .semibold))
                Spacer()
                if let failure = model.openFailure {
                    Text(failure).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.6))
                        .lineLimit(1).transition(.opacity)
                } else if invalid {
                    Text("Not a valid link").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.6))
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white.opacity(0.85))

            // One capsule: link field, clear, and the submit button inset at the end so
            // the two share a centre line (48 pt field, 38 pt button, 5 pt inset all round).
            HStack(spacing: 8) {
                TextField("", text: $link, prompt: Text("Paste a Vercel link").foregroundStyle(.white.opacity(0.5)))
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused(focused)
                    .onSubmit(submit)
                    .onChange(of: link) { withAnimation(.easeOut(duration: 0.15)) { invalid = false } }
                if !link.isEmpty {
                    Button { link = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.55))
                            .frame(width: 28, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
                Button(action: submit) {
                    ZStack {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .opacity(model.opening ? 0 : 1)
                            .scaleEffect(model.opening ? 0.5 : 1)
                        if model.opening {
                            ProgressView().controlSize(.small).tint(.black).transition(.opacity.combined(with: .scale(scale: 0.6)))
                        }
                    }
                        .foregroundStyle(.black)
                        .animation(.easeOut(duration: 0.18), value: model.opening)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(canSubmit ? 1 : 0.45)))
                        .contentShape(Circle().inset(by: -5)) // full-height touch target
                }
                .buttonStyle(PressScale())
                .disabled(!canSubmit || model.opening)
                .accessibilityLabel(model.opening ? "Opening prototype" : "Open prototype")
            }
            .padding(.leading, 18)
            .padding(.trailing, 5)
            .frame(height: 48)
            .background(Capsule().fill(.black.opacity(0.28)))
            .overlay(Capsule().strokeBorder(invalid ? Color(red: 1, green: 0.45, blue: 0.42) : .white.opacity(focused.wrappedValue ? 0.45 : 0.18), lineWidth: 1))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
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
        withAnimation(.easeOut(duration: 0.15)) { invalid = true }
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

private struct Wallpaper: View {
    var body: some View {
        // Sized by a clear backing + overlay so the image's intrinsic size can't push layout.
        Color.black
            .overlay {
                if let image = UIImage(named: "wallpaper.webp") ?? Bundle.main.path(forResource: "wallpaper", ofType: "webp").flatMap(UIImage.init(contentsOfFile:)) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
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
        bottom = max(safe.bottom, 12) + 24
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
        let target: UIVisualEffect? = active ? UIBlurEffect(style: .systemThinMaterialDark) : nil
        guard (v.effect == nil) != (target == nil) else { return }
        UIViewPropertyAnimator(duration: active ? 0.45 : 0.32, dampingRatio: 1) { v.effect = target }.startAnimation()
    }
}
