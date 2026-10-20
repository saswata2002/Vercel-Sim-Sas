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
    @State private var joinBlur = false
    /// Pasting a link: the link card comes forward on its own, everything else steps away.
    @State private var pasteMode = false
    /// The Link Directory page's push: 0 = closed, 1 = open.
    @State private var push: CGFloat = 0
    /// The edge-back drag is down. Gesture state, so it also resets when the system cancels
    /// the drag (Notification Center, a call) and the page still settles.
    @GestureState private var edgeDragging = false
    /// The open morph has finished: the edge-back strip only takes touches after this, so a
    /// drag can't snap a half-grown card to full screen.
    @State private var pageSettled = false
    /// Bumped on every open/close, so a superseded close's completion can't hide the card.
    @State private var morphGen = 0
    /// The Link Directory widget's frame on screen (the morph's starting shape).
    @State private var widgetFrame: CGRect = .zero
    /// The morphing card is on screen (switched without animation, so it never fades).
    @State private var morphShown = false
    /// Which widget is (or was last) morphing into its page.
    private enum Expanded { case directory, push }
    @State private var expanded = Expanded.directory
    /// Pushed from web's frame on screen (its morph's starting shape).
    @State private var pushFrame: CGRect = .zero
    private var pageOpen: Bool { model.directoryOpen || model.pushPageOpen }
    private func closePage() { model.directoryOpen = false; model.pushPageOpen = false }
    /// The other widgets stepping away (0 → 1), faster than the morph so nothing overlaps.
    @State private var away: CGFloat = 0
    /// Critically damped, so the push never overshoots.
    /// Apple-style: smooth, with the slightest settle (like App Store cards opening).
    static let pushSpring = Animation.spring(duration: 0.5, bounce: 0.12)
    /// The link card's resting top edge and the keyboard's top edge (screen points), so
    /// in paste mode the card can sit just above the keyboard on any iPhone.
    @State private var cardMinY: CGFloat = 0
    /// The card's live height: it grows a little in paste mode (the back button's row), and
    /// the gap above the keyboard has to account for that.
    @State private var cardHeight: CGFloat = 0
    @State private var keyboardTop: CGFloat = UIScreen.main.bounds.height
    /// The field is focused but iOS reported no on-screen keyboard (a hardware keyboard).
    @State private var hardwareKeyboard = false
    /// How far the card travels down in paste mode: to `gap` above the keyboard.
    private var pasteDrop: CGFloat {
        guard cardHeight > 0 else { return 28 }
        // Before the keyboard reports in, aim for where it stood last time (or a typical
        // iPhone keyboard), so the card goes there in one move instead of two.
        let h = UIScreen.main.bounds.height
        let top = keyboardTop < h ? keyboardTop
            : hardwareKeyboard ? h - 34                     // no on-screen keyboard: near the bottom
            : (KeyboardMotion.lastTop ?? h - 336)
        return max(0, top - 16 - (cardMinY + cardHeight))   // reads as the sheets' 10 pt gap
    }
    private static let pasteSpring = Animation.spring(response: 0.46, dampingFraction: 0.86)
    /// The link the editor sheet shows (kept while the sheet animates away).
    @State private var editorLink: SavedLink?

    private func endPaste() {
        linkFocused = false
        withAnimation(KeyboardMotion.last) { pasteMode = false }
    }

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
                // Screen coordinates: the lock moves up with the finger, so a local translation
                // would shrink as it goes (a 270 pt swipe read as 100) and miss the threshold.
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .updating($swiping) { _, s, _ in s = true }
                    .onChanged { drag = $0.translation.height }
                    .onEnded { value in
                        debugLog("lock drag ended \(value.translation.height) predicted \(value.predictedEndTranslation.height)")
                        let flung = value.predictedEndTranslation.height < -height * 0.45
                        if value.translation.height < -120 || (value.translation.height < -30 && flung) {
                            // Hand the finger's position to the reveal: the lock keeps moving up
                            // from where it is, on the same spring as the prototype growing in.
                            withAnimation(AppModel.revealSpring) { drag = 0 }
                            linkFocused = false    // the keyboard leaves with the lock, not over the prototype
                            model.unlock()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                        }
                    }
            )

                // Lock-screen widget, below the clock like iOS widgets. Kept outside the
                // swipe / press-and-hold gestures above so editing the link never triggers them.
                VStack(spacing: m.gap) {
                    LinkWidget(focused: $linkFocused, pasteMode: pasteMode) { endPaste() }
                        // Its resting position only: the frame includes the paste offset below, and
                        // reading it while offset would chase its own movement.
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { r in
                            if !pasteMode { cardMinY = r.minY }
                            cardHeight = r.height
                        }
                        // Comes down to sit just above the keyboard while pasting.
                        .offset(y: pasteMode ? pasteDrop : 0)
                        // While the Link Directory opens: steps away up, blurring, like paste mode.
                        .modifier(StepAway(amount: away, dy: -24))
                        .zIndex(1)
                    // Saved links hug their rows, then fill the space below and scroll inside
                    // the card once they no longer fit (measured, so it holds on every screen).
                    Group {
                        LinkDirectoryWidget(directory: model.directory)
                            // Where the morph starts and ends; the real widget hides under it.
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { r in
                                // The open page's own widget keeps measuring, so the card closes
                                // onto its current size (links added or deleted meanwhile).
                                if !morphShown || expanded == .directory { widgetFrame = r }
                            }
                            .opacity(morphShown && expanded == .directory ? 0 : 1)
                            .modifier(StepAway(amount: expanded == .push ? away : 0, dy: -24))
                        // Links pushed from the web page.
                        PushWidget(hub: model.push, matchHeight: widgetFrame.height > 0 ? widgetFrame.height : nil)
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { r in
                                if !morphShown || expanded == .push { pushFrame = r }
                            }
                            .opacity(morphShown && expanded == .push ? 0 : 1)
                            .modifier(StepAway(amount: expanded == .directory ? away : 0, dy: 40))
                    }
                    .opacity(pasteMode ? 0 : 1)
                    .offset(y: pasteMode ? 40 : 0)
                    .blur(radius: pasteMode ? 6 : 0)
                    .allowsHitTesting(!pasteMode)
                    .accessibilityHidden(pasteMode)
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
                    .modifier(StepAway(amount: away, dy: 40))
                    .opacity(pasteMode ? 0 : 1)
                    .allowsHitTesting(!pasteMode)
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
              .allowsHitTesting(push < 0.01 && !morphShown)   // not while the card is still shrinking back
        }
        // Link Directory ▸ the widget morphs into its own page, driven by `push` (0 the widget,
        // 1 the page); the back swipe drags it directly so the morph follows the finger.
        .overlay {
            GeometryReader { geo in
                let m = LockMetrics(size: geo.size, safe: model.device.safeArea)
                let w = geo.size.width
                // Always mounted (hidden at rest), so the morph animates from the widget's
                // frame instead of being inserted already full screen.
                Group {
                    // Both stay mounted (only the active one shows), so neither is ever inserted
                    // mid-animation, which would render it straight at its end state.
                    ZStack {
                        LinkDirectoryMorph(directory: model.directory, progress: expanded == .directory ? push : 0,
                                           from: widgetFrame, screen: geo.size,
                                           top: m.clockTop, margin: m.margin) { closePage() }
                            .opacity(expanded == .directory ? 1 : 0)
                            .allowsHitTesting(expanded == .directory)
                        PushMorph(hub: model.push, progress: expanded == .push ? push : 0, from: pushFrame, screen: geo.size,
                                  top: m.clockTop, margin: m.margin,
                                  matchHeight: widgetFrame.height > 0 ? widgetFrame.height : nil) { closePage() }
                            .opacity(expanded == .push ? 1 : 0)
                            .allowsHitTesting(expanded == .push)
                    }
                        .overlay(alignment: .leading) {
                            // Interactive back from the left edge.
                            Color.clear.frame(width: 24).contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                        .updating($edgeDragging) { _, s, _ in s = true }
                                        .onChanged { v in
                                            push = min(1, max(0, 1 - v.translation.width / w))
                                            away = min(1, max(0, (push - 0.35) / 0.4))
                                        }
                                        .onEnded { v in
                                            if v.translation.width > w * 0.35 || v.predictedEndTranslation.width > w * 0.5 {
                                                UISelectionFeedbackGenerator().selectionChanged()
                                                closePage()
                                            } else {
                                                withAnimation(Self.pushSpring) { push = 1; away = 1 }
                                            }
                                        }
                                )
                                .allowsHitTesting(pageOpen && pageSettled)
                        }
                }
                .opacity(morphShown ? 1 : 0)
            }
            .ignoresSafeArea()
            .allowsHitTesting(pageOpen)
            .accessibilityHidden(!pageOpen)
        }
        // One page at a time: if both were asked for at once (two fingers), the later one wins
        // only when the other isn't already open.
        .onChange(of: model.directoryOpen) { _, open in
            guard open else { return }
            if model.pushPageOpen { model.directoryOpen = false } else { expanded = .directory }
        }
        .onChange(of: model.pushPageOpen) { _, open in
            guard open else { return }
            if model.directoryOpen { model.pushPageOpen = false } else { expanded = .push }
        }
        .onChange(of: pageOpen) { _, open in
            morphGen += 1
            let gen = morphGen
            pageSettled = false
            if open {
                // Show the card (instantly, over the widget), then grow it on the next frame.
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { morphShown = true }
                withAnimation(.easeOut(duration: 0.16)) { away = 1 }
                // A beat after the others start leaving, so the card never grows over them.
                withAnimation(Self.pushSpring.delay(0.05)) { push = 1 } completion: {
                    if gen == morphGen, pageOpen { pageSettled = true }
                }
            } else {
                withAnimation(.easeOut(duration: 0.3).delay(0.22)) { away = 0 }
                withAnimation(Self.pushSpring) { push = 0 } completion: {
                    if gen == morphGen, !pageOpen {
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { morphShown = false }
                    }
                }
            }
        }
        .onChange(of: edgeDragging) { _, dragging in
            // An interrupted edge drag (no onEnded): settle to where the page belongs.
            if !dragging, push > 0, push < 1 {
                let open = pageOpen
                withAnimation(Self.pushSpring) { push = open ? 1 : 0; away = open ? 1 : 0 }
            }
        }
        // Editing a saved link: a heavy blur over the whole lock screen. The sheet is its own
        // presentation above this, so it stays sharp.
        .onChange(of: swiping) { _, down in
            guard !down, drag != 0 else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
        }
        .overlay { BackdropBlur(active: editBlur || guideBlur || joinBlur).allowsHitTesting(false) }
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
        // The guide: only from the Quick tour button (it never opens by itself).
        .lwFloatingSheet(isPresented: $model.guideOpen, height: 452, scrim: 0.2) { FirstRunGuide() }
        .onChange(of: model.guideOpen) { _, on in guideBlur = on }
        // Pushed from web ▸ Set up: join a room.
        .lwFloatingSheet(isPresented: $model.pushJoinOpen, height: 520, scrim: 0.2, fit: true) { PushJoinSheet(hub: model.push) }
        .onChange(of: model.pushJoinOpen) { _, on in joinBlur = on }
        // A lock screen mounted with a sheet already up starts with its blur on, too.
        .onAppear {
            editBlur = model.editingLink != nil
            guideBlur = model.guideOpen
            joinBlur = model.pushJoinOpen
        }
        // Paste mode follows the field, and holds while a pasted link is opening.
        .onChange(of: linkFocused) { _, on in
            // On the keyboard's own curve, so the cards move with it, not before or after it.
            if on { withAnimation(KeyboardMotion.last) { pasteMode = true } }
            else if !model.opening, !model.linkSubmitting { withAnimation(KeyboardMotion.last) { pasteMode = false } }
        }
        .onChange(of: model.linkSubmitting) { _, on in
            // A submit that didn't open anything (an invalid link): paste mode ends now.
            if !on, !model.opening, !linkFocused { withAnimation(Self.pasteSpring) { pasteMode = false } }
        }
        .onChange(of: model.opening) { _, on in
            if !on, !linkFocused { withAnimation(Self.pasteSpring) { pasteMode = false } }
        }
        .onChange(of: model.lockVisible) { _, visible in
            // Leaving: put the keyboard away (paste mode animates out with the field, or holds
            // while a link opens). Back again: never come back stuck in paste mode.
            if !visible { linkFocused = false; closePage() }
            else if !linkFocused { pasteMode = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let top = end.minY < UIScreen.main.bounds.height ? end.minY : UIScreen.main.bounds.height
            // Focused, yet nothing on screen: a hardware keyboard. (While hiding, the field is
            // already unfocused, so a paste-mode hold keeps aiming where the keyboard was.)
            if linkFocused { hardwareKeyboard = top >= UIScreen.main.bounds.height }
            withAnimation(KeyboardMotion.animation(n)) { keyboardTop = top }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { n in
            withAnimation(KeyboardMotion.animation(n)) { keyboardTop = UIScreen.main.bounds.height }
        }
    }
}

/// "Open a prototype" widget: a clear link field, Paste, and Submit.
private struct LinkWidget: View {
    @EnvironmentObject private var model: AppModel
    var focused: FocusState<Bool>.Binding
    var pasteMode = false
    var onBack: () -> Void = {}
    @State private var link = ""
    @State private var invalid = false
    @State private var shake: CGFloat = 0

    private var canSubmit: Bool { !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// A submit is waiting for the keyboard to go: a second tap meanwhile is ignored.
    @State private var pending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if pasteMode {
                    LWIconButton(symbol: "chevron.left", look: .soft, size: 30, action: onBack)
                        .accessibilityLabel("Back")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
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
                    .disabled(!canSubmit || model.opening || pending)
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
        guard canSubmit, !model.opening, !pending else { return }
        guard AppModel.normalize(link) != nil else { rejected(); return }
        // Keyboard first, and open only once it has fully gone: a reveal that overlaps the
        // keyboard's dismissal can leave the lock screen drawn in place.
        let target = link
        let keyboardUp = focused.wrappedValue
        pending = true
        model.linkSubmitting = true
        focused.wrappedValue = false
        KeyboardWait.afterHidden(keyboardUp) {
            pending = false
            if !model.open(target) { rejected() }
            model.linkSubmitting = false
        }
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
            token = nil          // breaks the block → fire → token cycle
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

/// The other widgets stepping away while one takes the screen: they drift (by `dy`), blur
/// and fade, the same as in paste mode.
/// Driven by its own quick timing (`away` in LockScreenView): the widgets clear out before the
/// growing card reaches them, and come back only once it has shrunk.
private struct StepAway: ViewModifier, Animatable {
    var amount: CGFloat
    var dy: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        let raw = min(max(amount, 0), 1)
        let t = raw * raw * (3 - 2 * raw)
        return content
            .offset(y: dy * t)
            .blur(radius: 8 * t)
            .scaleEffect(1 - 0.04 * t)
            .opacity(1 - Double(t))
    }
}
