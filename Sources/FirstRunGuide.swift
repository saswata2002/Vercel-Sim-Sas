import SwiftUI

/// How to use Vercel Sim: five short pages, each one big moving picture, a title and a line.
/// It opens by itself the first time the app starts, and from the ⓘ on the lock screen.
struct FirstRunGuide: View {
    @Environment(\.floatingDismiss) private var dismiss
    @State private var page = 0
    /// Horizontal drag of the pages, and the pager's width (for slide distances).
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 0
    /// True while a finger is on the pages; resets even if the system cancels the drag.
    @GestureState private var paging = false
    /// A slide animating to the next/previous page (`settleDir`), not yet committed.
    @State private var settleDir = 0
    @State private var settleToken = 0

    static let seenKey = "guideSeen"

    fileprivate enum Art { case open, directory, swipeUp, options, iterations }
    private let pages: [(art: Art, title: String, line: String)] = [
        (.open, "Paste a link", "Any Vercel link opens full screen at 375 px."),
        (.options, "Options, anywhere", "Double-tap with two fingers."),
        (.iterations, "Switch iterations", "The prototype's 1 · 2 · 3 live in Options."),
        (.directory, "Saved for later", "Swipe a link to edit or delete it."),
        (.swipeUp, "Swipe up to return", "Reopens the last prototype you had open."),
    ]

    /// How long each page shows before the guide moves on by itself (round and round).
    private static let dwell: Duration = .seconds(5)

    private var n: Int { pages.count }
    private func wrap(_ i: Int) -> Int { (i % n + n) % n }

    var body: some View {
        VStack(spacing: 0) {

            // An endless pager: only the previous, current and next pages exist, keyed by
            // page, so stepping past the last simply brings the first in from the right.
            GeometryReader { geo in
                ZStack {
                    ForEach([-1, 0, 1].map { (k: $0, i: wrap(page + $0)) }, id: \.i) { slot in
                        pageView(pages[slot.i], active: slot.k == 0)
                            .frame(width: geo.size.width)
                            .offset(x: CGFloat(slot.k) * geo.size.width + drag)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .updating($paging) { _, s, _ in s = true }
                        .onChanged { v in
                            // A new swipe while the last one is still sliding: land that one first.
                            if settleDir != 0 { commitSettle() }
                            drag = v.translation.width
                        }
                        .onEnded { v in
                            let w = geo.size.width, travel = v.predictedEndTranslation.width
                            step(travel < -w * 0.3 ? 1 : travel > w * 0.3 ? -1 : 0)
                        }
                )
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, w in width = w }
            }
            .clipped()
            // An interrupted drag (call, backgrounding) never ends: settle back instead of
            // leaving two pages half on screen.
            .onChange(of: paging) { _, down in
                if !down, settleDir == 0, drag != 0 { step(0) }
            }
            // Plays through by itself, round and round; a swipe or a dot restarts the wait.
            .task(id: page) {
                try? await Task.sleep(for: Self.dwell)
                // Never step under a finger or mid-slide; wait for the page to be at rest.
                while !Task.isCancelled, paging || settleDir != 0 || drag != 0 {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                guard !Task.isCancelled else { return }
                step(1)
            }

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? LW.ink : LW.wash(6))
                        .frame(width: i == page ? 18 : 6, height: 6)
                        .padding(.vertical, 8)                       // a bigger target than the dot
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if settleDir != 0 { commitSettle() }
                            withAnimation(LW.easeOut(260)) { page = i; drag = 0 }
                        }
                }
            }
            .animation(LW.easeOut(240), value: page)
            .padding(.bottom, 12)
            .accessibilityHidden(true)

            Button("Got It") {
                UISelectionFeedbackGenerator().selectionChanged()
                finish()
            }
            // A pill, concentric with the card's bottom corners at the same 16 pt margin.
            .buttonStyle(LWButton(variant: .primary, radius: LWFloatingSheet<EmptyView>.innerRadius, height: 52, fill: true))
            .padding(.horizontal, LWFloatingSheet<EmptyView>.pad)
            .padding(.bottom, LWFloatingSheet<EmptyView>.pad)
        }
        .environment(\.colorScheme, .dark)
        .onDisappear { UserDefaults.standard.set(true, forKey: Self.seenKey) }
    }

    /// Slide one page forward (1), back (−1), or settle back (0); then make the page that
    /// slid in the current one, which is already exactly where it sits, so nothing jumps.
    private func step(_ dir: Int) {
        guard width > 0 else { return }
        if settleDir != 0 { commitSettle() }
        settleDir = dir
        settleToken &+= 1
        let token = settleToken
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            drag = -CGFloat(dir) * width
        } completion: {
            // Skip if a newer swipe already landed this one.
            guard token == settleToken else { return }
            if dir == 0 { settleDir = 0 } else { commitSettle() }
        }
    }

    /// Make the page that slid in the current one, at once (it's already in place).
    private func commitSettle() {
        let dir = settleDir
        settleDir = 0
        settleToken &+= 1
        guard dir != 0 else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            page = wrap(page + dir)
            drag = 0
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        dismiss()
    }

    private var well: RoundedRectangle {
        RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous)
    }

    private func pageView(_ p: (art: Art, title: String, line: String), active: Bool) -> some View {
        VStack(spacing: 0) {
            GuideArt(art: p.art, active: active)
                .frame(maxWidth: .infinity)
                .frame(height: 236, alignment: .top)      // the phone rises from the bottom edge
                .background(LWDotGrid())
                .background(well.fill(LW.wash(1)))
                .clipShape(well)
                .overlay(well.strokeBorder(LW.line, lineWidth: 1))
                // The same 16 pt margin on top and sides, corners concentric with the card's.
                .padding([.horizontal, .top], LWFloatingSheet<EmptyView>.pad)
                .padding(.bottom, 24)
            Text(p.title)
                .font(LW.sans(24, .semibold))
                .foregroundStyle(LW.ink)
                .padding(.bottom, 6)
            Text(p.line)
                .font(LW.body)
                .foregroundStyle(LW.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The kit's dot grid, for the picture wells.
private struct LWDotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 16
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)), with: .color(LW.ink.opacity(0.07)))
                    x += step
                }
                y += step
            }
        }
    }
}

// MARK: - pictures
//
// The original simple pictures (a link field, saved rows, a small phone, the iteration
// chips), each set on a raised tray with spring motion. No touch pointers.

private struct GuideArt: View {
    let art: FirstRunGuide.Art
    let active: Bool

    var body: some View {
        ZStack {
            // A soft light behind the picture.
            RadialGradient(colors: [LW.ink.opacity(0.09), .clear], center: .center, startRadius: 4, endRadius: 170)
            switch art {
            case .open: OpenArt(active: active)
            case .directory: DirectoryArt(active: active)
            case .swipeUp: SwipeUpArt(active: active)
            case .options: OptionsArt(active: active)
            case .iterations: IterationsArt(active: active)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Runs `step` in a loop while `active`, cancelling when the page leaves.
private struct Looping: ViewModifier {
    let active: Bool
    let reset: () -> Void
    let step: @MainActor () async -> Void
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, on in
                task?.cancel()
                // Reset only when the page comes back, so one sliding away keeps its frame.
                guard on else { return }
                reset()
                task = Task { @MainActor in
                    while !Task.isCancelled { await step() }
                }
            }
            .onDisappear { task?.cancel(); task = nil }
    }
}

private func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

// MARK: shared pieces

/// A raised kit tray: card fill, hairline, a soft drop shadow.
private struct Tray: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(LW.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(LW.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

/// The small label above a picture, as on the iterations page.
private struct ArtLabel: View {
    let text: String
    var body: some View { Text(text).font(LW.micro).tracking(1.2).foregroundStyle(LW.muted) }
}

/// A small phone: lit bezel edge, Dynamic Island, rounded screen.
private struct PhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        let outer = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 20, style: .continuous)
        ZStack(alignment: .top) {
            outer.fill(Color(white: 0.03))
            content
                .frame(width: 104, height: 202)
                .clipShape(inner)
                .padding(4)
            Capsule().fill(.black).frame(width: 30, height: 9).padding(.top, 9)
        }
        .frame(width: 112, height: 210)
        .overlay(outer.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
    }
}

/// The prototype in the phone: a plain white screen.
private struct ProtoScreen: View {
    var body: some View {
        Color.white.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The lock screen for the phone: dark canvas, the two kit cards.
private struct LockScreenMini: View {
    var body: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(LW.ink.opacity(0.6)).frame(width: 34, height: 4)
                RoundedRectangle(cornerRadius: 4).fill(LW.wash(4)).frame(height: 12)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LW.card))
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(LW.ink.opacity(0.6)).frame(width: 30, height: 4)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(LW.wash(5)).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: 1).fill(LW.ink.opacity(0.45)).frame(width: 36, height: 3)
                            RoundedRectangle(cornerRadius: 1).fill(LW.ink.opacity(0.2)).frame(width: 46, height: 3)
                        }
                    }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LW.card))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LW.bg)
    }
}

/// A spinning arc, driven by the clock so it needs no state.
private struct Spinner: View {
    var body: some View {
        TimelineView(.animation) { t in
            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(LW.onInk, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 15, height: 15)
                .rotationEffect(.degrees(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8 * 360))
        }
    }
}

// MARK: the five pictures

/// A paste: the empty field is focused with a blinking caret, the whole link drops in
/// highlighted, then the arrow lights up, is pressed, spins and ticks.
private struct OpenArt: View {
    let active: Bool
    private static let url = "my-app.vercel.app"
    private enum Phase { case idle, loading, done }
    @State private var focused = false
    @State private var pasted = false
    @State private var highlight = false
    @State private var phase = Phase.idle
    @State private var down = false
    @State private var tick = false

    var body: some View {
        VStack(spacing: 16) {
            ArtLabel(text: "OPEN A PROTOTYPE")
            HStack(spacing: 2) {
                ZStack(alignment: .leading) {
                    // Placeholder (the caret sits at its start), then the pasted link with a
                    // fading selection behind it.
                    Text("Paste a Vercel link")
                        .font(LW.body).foregroundStyle(LW.muted)
                        .opacity(pasted ? 0 : 1)
                        // Gone at once when the link lands (as in iOS), but it still moves
                        // with the sheet as it slides in.
                        .animation(nil, value: pasted)
                    Caret(blinking: true)
                        .offset(x: -3)
                        .opacity(focused && !pasted ? 1 : 0)
                    Text(Self.url)
                        .font(LW.body).foregroundStyle(LW.ink)
                        .padding(.horizontal, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.35, green: 0.55, blue: 1).opacity(highlight ? 0.45 : 0)))
                        .padding(.horizontal, -2)
                        .opacity(pasted ? 1 : 0)
                        .scaleEffect(pasted ? 1 : 0.96, anchor: .leading)
                }
                .lineLimit(1)
                Caret(blinking: true)                         // after the pasted link
                    .opacity(pasted && !highlight && phase == .idle ? 1 : 0)
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(pasted ? LW.ink : LW.wash(4))
                    switch phase {
                    case .idle:
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(pasted ? LW.onInk : LW.muted)
                    case .loading:
                        Spinner()
                    case .done:
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(LW.onInk)
                            .scaleEffect(tick ? 1 : 0.3)
                            .opacity(tick ? 1 : 0)
                    }
                }
                .frame(width: 36, height: 36)
                .scaleEffect(down ? 0.86 : 1)
            }
            .padding(.leading, 14).padding(.trailing, 6)
            .lwField(focused: focused, height: 48)
            .padding(8)
            .modifier(Tray(radius: LW.R.xl + 8))
            .padding(.horizontal, 28)
        }
        .modifier(Looping(active: active, reset: {
            focused = false; pasted = false; highlight = false
            phase = .idle; down = false; tick = false
        }) {
            focused = false; pasted = false; highlight = false; phase = .idle; tick = false
            await wait(450)
            withAnimation(LW.easeOut(200)) { focused = true }             // tap the field
            await wait(1100)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pasted = true; highlight = true }   // paste
            await wait(450)
            withAnimation(.easeOut(duration: 0.5)) { highlight = false }  // selection fades
            await wait(550)
            withAnimation(LW.easeOut(90)) { down = true }                // press the arrow
            await wait(130)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { down = false }
            phase = .loading
            await wait(800)
            phase = .done
            withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { tick = true }
            await wait(1300)
        })
    }
}

/// A text caret that blinks like the system one while `blinking`.
private struct Caret: View {
    var blinking: Bool
    var body: some View {
        TimelineView(.animation) { t in
            let on = !blinking || t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) < 0.55
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 0.35, green: 0.55, blue: 1))
                .frame(width: 2, height: 20)
                .opacity(on ? 1 : 0)
        }
    }
}

/// The Link Directory card; the middle link swipes left to Delete, back, right to Edit, back.
private struct DirectoryArt: View {
    let active: Bool
    @State private var offset: CGFloat = 0
    @State private var finger = false

    private let rows: [(String, String, String)] = [
        ("H", "noon — Home", "product-upscale.vercel.app"),
        ("P", "noon — PLP", "product-upscale.vercel.app/plp"),
        ("D", "noon PDP · v2", "ifn-interaction.vercel.app"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Link Directory").font(LW.sans(15, .semibold)).foregroundStyle(LW.ink)
                LWCountPill(text: "3")
            }
            .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    if i > 0 { LWHairline(inset: 40) }
                    if i == 1 { swipeRow(rows[i]) } else { row(rows[i]) }
                }
            }
        }
        .padding(12)
        .modifier(Tray(radius: LW.R.tile))
        .padding(.horizontal, 26)
        .modifier(Looping(active: active, reset: { offset = 0; finger = false }) {
            let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)
            for dx in [-92.0, 92.0] {
                await wait(600)
                withAnimation(LW.easeOut(180)) { finger = true }
                await wait(220)
                withAnimation(spring) { offset = dx }
                await wait(420)
                withAnimation(LW.easeOut(200)) { finger = false }
                await wait(1000)
                withAnimation(spring) { offset = 0 }
            }
            await wait(300)
        })
    }

    private func row(_ r: (String, String, String)) -> some View {
        HStack(spacing: 10) {
            LWLetterBadge(letter: r.0, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.1).font(LW.sans(13, .medium)).foregroundStyle(LW.ink)
                Text(r.2).font(LW.sans(11)).foregroundStyle(LW.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 46)
        .background(LW.card)
    }

    private func swipeRow(_ r: (String, String, String)) -> some View {
        ZStack {
            HStack {
                action("pencil", "Edit", fill: LW.wash(5), fg: LW.ink).opacity(offset > 0 ? 1 : 0)
                Spacer()
                action("trash", "Delete", fill: LW.dangerSolid, fg: .white).opacity(offset < 0 ? 1 : 0)
            }
            row(r)
                .offset(x: offset)
        }
        .frame(height: 46)
        .clipped()                                   // slides under the card's edge, as in the app
    }

    private func action(_ symbol: String, _ label: String, fill: Color, fg: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(label).font(LW.caption)
        }
        .foregroundStyle(fg)
        .frame(width: 82, height: 38)
        .background(RoundedRectangle(cornerRadius: LW.R.xl, style: .continuous).fill(fill))
    }
}

/// The lock screen slides up the phone under a finger, uncovering the prototype; chevrons
/// hint the direction first.
private struct SwipeUpArt: View {
    let active: Bool
    @State private var progress: CGFloat = 0
    @State private var finger = false
    @State private var fingerY: CGFloat = 0
    @State private var lockBack: Double = 1
    @State private var hint: CGFloat = 0

    var body: some View {
        PhoneFrame {
            ZStack {
                ProtoScreen()
                    .scaleEffect(0.92 + 0.08 * progress)
                    .opacity(0.35 + 0.65 * progress)
                LockScreenMini()
                    .overlay(alignment: .bottom) {
                        // Swipe-up hint: chevrons rising and fading.
                        VStack(spacing: -4) {
                            ForEach(0..<2, id: \.self) { i in
                                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(LW.ink.opacity(0.7 * (1 - hint) * (i == 0 ? 1 : 0.6)))
                            }
                        }
                        .offset(y: -30 - 10 * hint)
                    }
                    .offset(y: -202 * progress)
                    .opacity(lockBack)
            }
        }
        .modifier(Looping(active: active, reset: { progress = 0; finger = false; fingerY = 0; lockBack = 1; hint = 0 }) {
            progress = 0; fingerY = 0; hint = 0
            withAnimation(.easeOut(duration: 0.9)) { hint = 1 }
            await wait(800)
            withAnimation(LW.easeOut(160)) { finger = true }
            await wait(240)
            withAnimation(.easeInOut(duration: 0.5)) { fingerY = 1 }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { progress = 1 }
            await wait(420)
            withAnimation(LW.easeOut(200)) { finger = false }
            await wait(1700)
            lockBack = 0
            progress = 0
            withAnimation(LW.easeOut(380)) { lockBack = 1 }
            await wait(450)
        })
    }
}

/// Two fingers double-tap the prototype; the floating Options sheet rises in the phone.
private struct OptionsArt: View {
    let active: Bool
    @State private var fingers = false
    @State private var down = false
    @State private var ripple: CGFloat = 0
    @State private var sheet = false

    var body: some View {
        PhoneFrame {
            ZStack(alignment: .bottom) {
                ProtoScreen()
                Color.black.opacity(sheet ? 0.3 : 0)
                // The floating sheet: inset, all corners rounded, chips and rows.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(LW.ink.opacity(0.8)).frame(width: 30, height: 5)
                        Spacer()
                        Capsule().strokeBorder(LW.lineStrong, lineWidth: 1).frame(width: 22, height: 11)
                    }
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4).fill(i == 0 ? LW.ink : LW.wash(5)).frame(width: 15, height: 15)
                        }
                    }
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(LW.wash(4)).frame(height: 12)
                    }
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LW.bg))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LW.line, lineWidth: 1))
                .padding(4)
                .offset(y: sheet ? 0 : 140)
                // Two fingers.
                HStack(spacing: 18) {
                    TouchDot(down: down)
                    TouchDot(down: down)
                }
                .frame(maxHeight: .infinity)
                .opacity(fingers ? 1 : 0)
            }
        }
        .modifier(Looping(active: active, reset: { fingers = false; down = false; ripple = 0; sheet = false }) {
            sheet = false
            await wait(700)
            withAnimation(LW.easeOut(180)) { fingers = true }
            await wait(260)
            for _ in 0..<2 {
                ripple = 0
                withAnimation(LW.easeOut(90)) { down = true }
                await wait(120)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { down = false }
                withAnimation(.easeOut(duration: 0.45)) { ripple = 1 }
                await wait(170)
            }
            withAnimation(LW.easeOut(220)) { fingers = false }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { sheet = true }
            await wait(1900)
            withAnimation(LW.easeOut(300)) { sheet = false }
            await wait(500)
        })
    }
}

/// A touch: a plain translucent dot that dips when it taps.
private struct TouchDot: View {
    var down = false
    var body: some View {
        Circle()
            .fill(Color.black.opacity(down ? 0.28 : 0.18))
            .frame(width: 20, height: 20)
            .scaleEffect(down ? 0.8 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The iteration chips, as before, with motion: one ink selection slides between them on a
/// spring as a fingertip taps 1 → 2 → 3, the big number above rolls to match, then ↺ spins
/// and everything returns to 1.
private struct IterationsArt: View {
    let active: Bool
    @State private var selected = 0
    @State private var target = 1
    @State private var pressed: Int?
    @State private var finger = false
    @State private var ripple: CGFloat = 0
    @State private var spin: Double = 0

    private static let cell: CGFloat = 50, gap: CGFloat = 8, inset: CGFloat = 8
    private let labels = ["1", "2", "3", "↺"]
    private func x(_ i: Int) -> CGFloat { Self.inset + CGFloat(i) * (Self.cell + Self.gap) }

    var body: some View {
        VStack(spacing: 18) {
            // The current iteration, big, in the pixel face; rolls as it changes.
            VStack(spacing: 4) {
                ArtLabel(text: "ITERATION")
                Text(String(format: "%02d", selected + 1))
                    .font(LW.pixel(44))
                    .foregroundStyle(LW.ink)
                    .contentTransition(.numericText(value: Double(selected)))
            }

            ZStack(alignment: .topLeading) {
                // The sliding selection.
                RoundedRectangle(cornerRadius: LW.R.control, style: .continuous)
                    .fill(LW.ink)
                    .frame(width: Self.cell, height: Self.cell)
                    .shadow(color: LW.ink.opacity(0.25), radius: 10)
                    .offset(x: x(selected), y: Self.inset)
                HStack(spacing: Self.gap) {
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i])
                            .font(LW.sans(18, .semibold))
                            .foregroundStyle(i == selected ? LW.onInk : LW.ink)
                            .rotationEffect(.degrees(i == 3 ? spin : 0))
                            .frame(width: Self.cell, height: Self.cell)
                            .background {
                                if i != selected {
                                    RoundedRectangle(cornerRadius: LW.R.control, style: .continuous).fill(LW.wash(4))
                                }
                            }
                            .scaleEffect(pressed == i ? 0.88 : 1)
                    }
                }
                .padding(Self.inset)
            }
            .background(RoundedRectangle(cornerRadius: LW.R.control + Self.inset, style: .continuous).fill(LW.card))
            .overlay(RoundedRectangle(cornerRadius: LW.R.control + Self.inset, style: .continuous).strokeBorder(LW.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }
        .modifier(Looping(active: active, reset: { selected = 0; target = 1; pressed = nil; finger = false; ripple = 0; spin = 0 }) {
            for next in [1, 2, 3] {                      // 2, 3, then ↺
                await wait(700)
                target = next
                ripple = 0
                withAnimation(LW.easeOut(160)) { finger = true }
                await wait(320)
                withAnimation(LW.easeOut(90)) { pressed = next }
                await wait(120)
                withAnimation(.easeOut(duration: 0.45)) { ripple = 1 }
                if next == 3 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { pressed = nil; spin -= 360; selected = 0 }
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { pressed = nil; selected = next }
                }
                await wait(220)
                withAnimation(LW.easeOut(220)) { finger = false }
            }
            await wait(500)
        })
    }
}
