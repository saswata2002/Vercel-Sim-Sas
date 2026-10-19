import SwiftUI
import UIKit

// Lightweight UI (github:ayaneshu/lightweight-ui-kit v0.2, https://lightweight-ui-kit.vercel.app),
// the noon internal UI kit, as SwiftUI. Values are the kit's own tokens (dist/tokens.json):
// ink on paper, hairline surfaces and no glass, Geist for UI text, Geist Pixel Square for big
// figures, one ease-out curve, 97% press. Light and dark follow the kit's two themes.

enum LW {
    // MARK: colour (themes.light / themes.dark)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let bg = dyn(0xFFFFFF, 0x111214)
    static let card = dyn(0xFFFFFF, 0x18191C)
    static let raised = dyn(0xFFFFFF, 0x2A2B30)
    static let field = dyn(0xFFFFFF, 0x1D1E22)
    static let ink = dyn(0x18191D, 0xECECEE)
    static let onInk = dyn(0xFFFFFF, 0x111214)
    static let muted = dyn(0x666879, 0x9C9FAD)
    static let line = dyn(0xEDEDEC, 0x2A2B30)
    static let lineStrong = dyn(0xE3E3E0, 0x34353B)
    static let lineField = dyn(0xC4C4C2, 0x4C4E56)
    static let danger = dyn(0xDA2424, 0xFF7B76)
    static let dangerSolid = dyn(0xDA2424, 0xDC2626)
    static let dangerBg = dyn(0xFEF2F2, 0x301618)
    static let open = dyn(0x15803D, 0x62D38E)
    /** The switch knob when on: white on the ink track; dark on the dark theme's light track. */
    static let switchKnobOn = dyn(0xFFFFFF, 0x111214)

    /// Ink at a low alpha — the kit's washes: 1 empty wells · 2 hover · 3 search · 4 pills,
    /// icon tiles, selected rows · 5 soft-button hover · 6 switch track (off).
    static func wash(_ n: Int) -> Color {
        let a: [CGFloat] = [0, 0.015, 0.03, 0.04, 0.06, 0.08, 0.12]
        let alpha = a[max(0, min(6, n))]
        return Color(uiColor: UIColor {
            ($0.userInterfaceStyle == .dark ? UIColor(hex: 0xECECEE) : UIColor(hex: 0x18191D)).withAlphaComponent(alpha)
        })
    }

    // MARK: type (fonts: Geist sans, Geist Pixel Square display)

    enum Weight { case regular, medium, semibold }

    static func sans(_ size: CGFloat, _ w: Weight = .regular) -> Font {
        let name: String
        switch w { case .regular: name = "Geist-Regular"; case .medium: name = "Geist-Medium"; case .semibold: name = "Geist-SemiBold" }
        return .custom(name, fixedSize: size)
    }
    /// Geist Pixel Square: display headings over 20 px and hero figures (the lock-screen clock).
    static func pixel(_ size: CGFloat) -> Font { .custom("GeistPixel-Square", fixedSize: size) }

    // Type scale (typeScale): token → font.
    static let title = sans(17, .semibold)      // card & dialog titles
    static let body = sans(15)                  // reading copy, option names
    static let bodyMedium = sans(15, .medium)
    static let ui = sans(14, .medium)           // controls, buttons, menu rows
    static let label = sans(13, .medium)        // secondary copy, field labels
    static let caption = sans(12, .medium)      // timestamps, tags
    static let micro = sans(11, .semibold)      // count pills, initials

    // MARK: radius (radii)
    enum R {
        static let md: CGFloat = 6, lg: CGFloat = 8, chip: CGFloat = 10, xl: CGFloat = 12, control: CGFloat = 14
        static let x2l: CGFloat = 16, tile: CGFloat = 20, panel: CGFloat = 22, sheet: CGFloat = 26, canvas: CGFloat = 28, device: CGFloat = 38
    }

    // MARK: motion (easings.out, durations)
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)          // swap
    static func easeOut(_ ms: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: ms / 1000) }
    static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - surfaces

/// A kit surface: card colour, 1 px `line` border, no shadow.
struct LWSurface: ViewModifier {
    var radius: CGFloat = LW.R.sheet
    var fill: Color = LW.card
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(LW.line, lineWidth: 1))
    }
}

extension View {
    func lwSurface(radius: CGFloat = LW.R.sheet, fill: Color = LW.card) -> some View { modifier(LWSurface(radius: radius, fill: fill)) }
}

// MARK: - floating sheets

/// Closes the floating sheet that contains the view (the counterpart of `dismiss`).
struct FloatingDismiss {
    let action: () -> Void
    func callAsFunction() { action() }
}
private struct FloatingDismissKey: EnvironmentKey { static let defaultValue = FloatingDismiss {} }
extension EnvironmentValues {
    var floatingDismiss: FloatingDismiss {
        get { self[FloatingDismissKey.self] }
        set { self[FloatingDismissKey.self] = newValue }
    }
}

/// A floating bottom sheet: a card inset from the screen's sides and bottom with every corner
/// rounded, a hairline border and a soft shadow, over a scrim. The system sheet always draws
/// its own glass edge on iOS 26, so this is drawn here instead. It slides up on a spring,
/// closes from its top edge (drag down), the scrim (tap) or the escape gesture, and rises with
/// the keyboard. `height` caps it; it shrinks when the keyboard leaves less room.
struct LWFloatingSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    var height: CGFloat
    var fill: Color = LW.card
    var scrim: Double = 0.4
    @ViewBuilder let sheet: () -> Sheet
    @State private var drag: CGFloat = 0
    /// True only while the top edge is held; resets even when the drag is cancelled.
    @GestureState private var holding = false
    /// How much of the screen the keyboard covers. Tracked here because some hosts (the lock
    /// screen) ignore the keyboard safe area, so the sheet would sit underneath it.
    @State private var keyboard: CGFloat = 0
    /// The overlay's bottom edge and the keyboard's top edge, both in screen points. The
    /// overlay can move as the keyboard appears (it follows its host), so the gap is worked
    /// out from both live edges: exactly `inset` above the keyboard on every device.
    @State private var hostMaxY: CGFloat = UIScreen.main.bounds.height
    @State private var keyboardTop: CGFloat = UIScreen.main.bounds.height

    static var inset: CGFloat { 10 }
    /// Concentric with the display's own corners (62 pt on iPhone 17 → 52), never under 28.
    static var radius: CGFloat { max(DisplayCorner.radius - inset, 28) }
    /// The margin inside the card, on every side, for anything with corners.
    static var pad: CGFloat { 16 }
    /// Corner radius for a shape `pad` in from the card's corner, so the two stay concentric.
    static var innerRadius: CGFloat { radius - pad }

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                // Measures the very box the card is laid out in (after the safe-area changes).
                Color.clear
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { hostMaxY = $0 }
                if isPresented {
                    Color.black.opacity(scrim)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .transition(.opacity)
                    card
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard)                                  // handled by `keyboard`
            .animation(.spring(response: 0.44, dampingFraction: 0.9), value: isPresented)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
                guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
                let covered = max(0, UIScreen.main.bounds.height - end.minY)
                withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
                    keyboard = covered
                    keyboardTop = covered > 0 ? end.minY : UIScreen.main.bounds.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) { keyboard = 0; keyboardTop = UIScreen.main.bounds.height }
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return sheet()
            .environment(\.floatingDismiss, FloatingDismiss { close() })
            .frame(maxWidth: .infinity)
            // No visible handle: the top edge still drags the sheet down to close.
            .overlay(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .updating($holding) { _, s, _ in s = true }
                        .onChanged { drag = $0.translation.height }
                        .onEnded { v in
                            if v.translation.height > 90 || v.predictedEndTranslation.height > 220 {
                                close()
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                            }
                        }
                )
                .accessibilityHidden(true)
            }
        .frame(maxHeight: height)                                // hugs its content up to `height`
        .background(shape.fill(fill))
        .clipShape(shape)
        .overlay(shape.strokeBorder(LW.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .environment(\.colorScheme, .dark)                // the app's sheets are always dark, even over a light page
        .padding(.horizontal, Self.inset)
        // Above the keyboard when it's up, the same `inset` as the sides on every device.
        .padding(.bottom, keyboard > 0 ? max(Self.inset, hostMaxY - keyboardTop + Self.inset) : Self.inset)
        .padding(.top, keyboard > 0 ? 54 : 0)                            // …and clear of the status bar
        .offset(y: max(0, drag) + min(0, drag) * 0.15)          // a little resistance upward
        .accessibilityAction(.escape) { close() }
        .onChange(of: holding) { _, down in
            guard !down, drag != 0, isPresented else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
        }
    }

    private func close() {
        debugLog("floating sheet: close")
        withAnimation(.spring(response: 0.38, dampingFraction: 0.92)) { isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { drag = 0 }
    }
}

extension View {
    func lwFloatingSheet<S: View>(isPresented: Binding<Bool>, height: CGFloat, fill: Color = LW.card, scrim: Double = 0.4,
                                  @ViewBuilder content: @escaping () -> S) -> some View {
        modifier(LWFloatingSheet(isPresented: isPresented, height: height, fill: fill, scrim: scrim, sheet: content))
    }
}

// MARK: - buttons

/// The kit's button weights: one primary per screen; the rest step down.
enum LWButtonVariant { case primary, secondary, soft, ghost, danger }

struct LWButton: ButtonStyle {
    var variant: LWButtonVariant = .primary
    /// sm 12 · md 14 · lg 16 corner radius (rows · dialog footers · page actions).
    var radius: CGFloat = LW.R.control
    var height: CGFloat = 44
    var fill = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(LW.ui)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
            .background(shape.fill(background(pressed: configuration.isPressed)))
            .overlay(shape.strokeBorder(variant == .secondary ? LW.lineStrong : .clear, lineWidth: 1))
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)                                  // press: 97%
            .animation(LW.easeOut(160), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary: return LW.onInk
        case .danger: return .white
        default: return LW.ink
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary: return LW.ink
        case .secondary: return pressed ? LW.wash(2) : LW.card
        case .soft: return pressed ? LW.wash(5) : LW.wash(4)
        case .ghost: return pressed ? LW.wash(3) : .clear
        case .danger: return LW.dangerSolid
        }
    }
}

/// 97% while held, on the kit's ease-out — for custom-drawn tappables.
struct LWPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(LW.easeOut(160), value: configuration.isPressed)
    }
}

/// Round icon button: `solid` = ink with on-ink glyph (the primary action), `ghost` = muted glyph.
struct LWIconButton: View {
    enum Look { case solid, ghost, soft }
    let symbol: String
    var look: Look = .solid
    var size: CGFloat = 36
    var busy = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small).tint(LW.onInk) }
            }
            .foregroundStyle(look == .solid ? (enabled ? LW.onInk : LW.muted) : look == .soft ? LW.ink : LW.muted)
            .frame(width: size, height: size)
            .background(Circle().fill(look == .solid ? (enabled ? LW.ink : LW.wash(4)) : look == .soft ? LW.wash(4) : .clear))
            .contentShape(Circle().inset(by: -6))
            .animation(LW.easeOut, value: enabled)
            .animation(LW.easeOut, value: busy)
        }
        .buttonStyle(LWPress())
    }
}

// MARK: - inputs

/// The kit's input: 12 px corners, a quiet `lineField` border at rest that turns ink on focus
/// (on the field itself — no ring), danger when invalid.
struct LWFieldBox: ViewModifier {
    var focused: Bool
    var invalid: Bool
    var height: CGFloat = 48
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LW.R.xl, style: .continuous)
        content
            .frame(height: height)
            .background(shape.fill(LW.field))
            .overlay(shape.strokeBorder(invalid ? LW.danger : focused ? LW.ink : LW.lineField, lineWidth: invalid || focused ? 1.5 : 1))
            .animation(LW.easeOut, value: focused)
            .animation(LW.easeOut, value: invalid)
    }
}

extension View {
    func lwField(focused: Bool, invalid: Bool = false, height: CGFloat = 48) -> some View {
        modifier(LWFieldBox(focused: focused, invalid: invalid, height: height))
    }
}

// MARK: - small pieces

/// Count pill: micro type on wash-4, full radius.
struct LWCountPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(LW.micro)
            .monospacedDigit()
            .foregroundStyle(LW.muted)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(LW.wash(4)))
    }
}

/// Letter badge (monogram): Bold initial on wash-4, `md` radius.
struct LWLetterBadge: View {
    let letter: String
    var size: CGFloat = 32
    var body: some View {
        Text(letter)
            .font(.custom("Geist-SemiBold", fixedSize: 13))
            .foregroundStyle(LW.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: LW.R.md + 2, style: .continuous).fill(LW.wash(4)))
    }
}

/// Icon tile: a glyph on wash-4 (empty states, settings rows).
struct LWIconTile: View {
    let symbol: String
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(LW.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: LW.R.xl, style: .continuous).fill(LW.wash(4)))
    }
}

/// The kit's switch: ink track when on, wash-6 when off, white knob with the hairline shadow.
struct LWSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? LW.ink : LW.wash(6)).frame(width: 40, height: 24)
                    Circle().fill(configuration.isOn ? LW.switchKnobOn : .white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                }
                .animation(LW.easeOut(180), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A hairline divider in `line`.
struct LWHairline: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(LW.line).frame(height: 1).padding(.leading, inset) }
}
