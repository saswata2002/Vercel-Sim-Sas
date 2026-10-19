import SwiftUI
import WebKit

/// The options sheet: everything that sits around the phone in the Mac app, as an iOS
/// bottom sheet. Opens with a two-finger double-tap anywhere (over a prototype or on the lock screen),
/// a two-finger press-and-hold, a shake, or press-and-hold on the lock screen.
struct ControlPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        // Over a running prototype: the browser-style menu that fits without scrolling.
        if model.currentURL != nil && !model.lockVisible {
            PrototypeMenu()
        } else {
            lockPanel
        }
    }

    private var lockPanel: some View {
        VStack(spacing: 0) {
            // Header: title + a small secondary Done (the sheet's only primary is "Open").
            HStack {
                Text("Options").font(LW.title).foregroundStyle(LW.ink)
                Spacer()
                Button("Done") { model.panelOpen = false }
                    .buttonStyle(LWButton(variant: .secondary, radius: LWFloatingSheet<EmptyView>.nested(6), height: 36))
            }
            // Done sits at the card's 16 pt margin, a pill concentric with its top corner.
            .padding(.leading, 20)
            .padding(.trailing, LWFloatingSheet<EmptyView>.pad)
            .padding(.top, LWFloatingSheet<EmptyView>.pad)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let switcher = model.switcher { iterationSection(switcher) }

                    // MARK: prototype
                    section("Prototype", footer: invalid ? "That isn\u{2019}t a valid link." : nil, footerIsError: true) {
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.system(size: 14, weight: .medium)).foregroundStyle(LW.muted)
                            TextField("", text: $draft, prompt: Text("Paste a Vercel link").foregroundStyle(LW.muted))
                                .font(LW.body)
                                .foregroundStyle(LW.ink)
                                .tint(LW.ink)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.go)
                                .focused($addressFocused)
                                .onSubmit(go)
                                .onChange(of: draft) { invalid = false }
                            LWIconButton(symbol: "arrow.right", look: .solid, size: 32, action: go)
                                .disabled(!canGo)
                                .accessibilityLabel("Open")
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 6)
                        .lwField(focused: addressFocused, invalid: invalid, height: 44)
                        .modifier(Shake(animatableData: invalid ? 1 : 0))
                        .padding(12)

                        if model.currentURL != nil {
                            LWHairline()
                            row("Reload", symbol: "arrow.clockwise") { model.reload(); model.panelOpen = false }
                            LWHairline(inset: 48)
                            row("Screenshot", symbol: "camera.viewfinder") { model.takeScreenshot() }
                            LWHairline(inset: 48)
                            row("Home", symbol: "house") { model.goHome() }
                        }
                    }

                    // MARK: links pushed from the web page
                    section("Push from the web", footer: PushHub.webAddress.map { "Push page: \($0)" } ?? "Pasting a room\u{2019}s invite link in the link field joins it too.") {
                        PushRoomRows(hub: model.push)
                    }

                    if !model.recents.isEmpty {
                        section("Recent prototypes") {
                            ForEach(Array(model.recents.enumerated()), id: \.element) { i, url in
                                if i > 0 { LWHairline(inset: 56) }
                                Button { model.open(url) } label: {
                                    HStack(spacing: 12) {
                                        LWLetterBadge(letter: String(AppModel.display(url).prefix(1)).uppercased(), size: 30)
                                        Text(AppModel.display(url)).font(LW.ui).foregroundStyle(LW.ink).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 8)
                                        if AppModel.sameDocument(URL(string: url), model.currentURL) {
                                            Text("Open").font(LW.micro).foregroundStyle(LW.open)
                                                .padding(.horizontal, 7).frame(height: 18)
                                                .background(Capsule().fill(LW.open.opacity(0.12)))
                                        }
                                    }
                                    .padding(.horizontal, 14).frame(minHeight: 52).contentShape(Rectangle())
                                }
                                .buttonStyle(LWRowPress())
                                .contextMenu {
                                    Button(role: .destructive) { model.removeRecents(at: IndexSet(integer: i)) } label: { Label("Remove", systemImage: "trash") }
                                }
                            }
                        }
                    }

                    // MARK: display (the Mac app's options popover)
                    section("Over prototypes", footer: "The lock screen always shows the status bar and home indicator.") {
                        toggle("Status bar", isOn: $model.showStatusBar)
                        LWHairline(inset: 14)
                        toggle("Home indicator", isOn: $model.showHomeIndicator)
                        LWHairline(inset: 14)
                        toggle("Scale 375 designs", detail: "Lays the page out at 375 pt and fills wider iPhones", isOn: $model.fitBase)
                        LWHairline(inset: 14)
                        toggle("Iteration pill on screen", isOn: $model.showIterationPill)
                        LWHairline(inset: 14)
                        toggle("Haptics", detail: "Plays the prototype\u{2019}s haptics on this iPhone", isOn: $model.hapticsOn)
                        LWHairline(inset: 14)
                        HStack {
                            Text("Appearance").font(LW.ui).foregroundStyle(LW.ink)
                            Spacer()
                            LWSegmented(options: Appearance.allCases.map { ($0, $0.label) }, selection: $model.appearance)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 52)
                    }

                    section("This device") {
                        let d = model.device
                        info("Model", d.name)
                        LWHairline(inset: 14)
                        info("Cutout", d.cutout)
                        LWHairline(inset: 14)
                        info("Screen", "\(Int(d.screen.width)) × \(Int(d.screen.height)) pt @\(Int(d.scale))x")
                        LWHairline(inset: 14)
                        info("Design layout", "\(Int(d.layout.width)) × \(Int(d.layout.height))" + (d.zoom == 1 ? " (1:1)" : String(format: " (×%.3f)", d.zoom)))
                        LWHairline(inset: 14)
                        info("Safe area", "\(Int(d.layoutSafeArea.top)) / \(Int(d.layoutSafeArea.bottom))")
                    }

                    // A settings-list destructive action: danger-outline, not solid.
                    Button { model.clearWebsiteData() } label: {
                        Label("Clear cookies & cache", systemImage: "trash").font(LW.ui).foregroundStyle(LW.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: LW.R.control, style: .continuous).strokeBorder(LW.danger.opacity(0.35), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LWPress())
                    .padding(.top, 22)

                    Text("Double-tap the screen with two fingers to open this sheet. You can also shake the iPhone, or press and hold with two fingers.")
                        .font(LW.sans(13)).foregroundStyle(LW.muted).lineSpacing(3)
                        .padding(.top, 12).padding(.horizontal, 4).padding(.bottom, 28)
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.colorScheme, .dark)   // the sheet stays dark over any prototype
        .onAppear {
            draft = model.currentURL.map { AppModel.display($0.absoluteString) } ?? ""
            if model.currentURL == nil { addressFocused = true }
        }
    }

    private var canGo: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: building blocks

    /// A section: muted label above a hairline card; an optional note (or error) below.
    private func section<Content: View>(_ title: String, footer: String? = nil, footerIsError: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(LW.label).foregroundStyle(LW.muted).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .lwSurface(radius: LWFloatingSheet<EmptyView>.innerRadius)
                .clipShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous))
            if let footer {
                Text(footer).font(LW.caption).foregroundStyle(footerIsError ? LW.danger : LW.muted).padding(.horizontal, 4)
            }
        }
        .padding(.top, 18)
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(LW.muted).frame(width: 22)
                Text(title).font(LW.ui).foregroundStyle(LW.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(LW.muted.opacity(0.6))
            }
            .padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(LWRowPress())
    }

    private func toggle(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LW.ui).foregroundStyle(LW.ink)
                if let detail { Text(detail).font(LW.caption).foregroundStyle(LW.muted) }
            }
        }
        .toggleStyle(LWSwitchStyle())
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(LW.ui).foregroundStyle(LW.ink)
            Spacer(minLength: 12)
            Text(value).font(LW.sans(13)).foregroundStyle(LW.muted).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
    }

    /// The prototype's own picker, lifted out: numbered iterations, then reset and any
    /// other controls it carries (e.g. Spec Sheet), in the page's order.
    @ViewBuilder
    private func iterationSection(_ switcher: Switcher) -> some View {
        section("Iteration") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(switcher.items) { item in
                        if item.index == switcher.items.first(where: { !$0.isOption })?.index {
                            Rectangle().fill(LW.line).frame(width: 1, height: 24).padding(.horizontal, 2)
                        }
                        Button { model.press(item) } label: {
                            Group {
                                if item.isOption { Text(item.text).font(LW.sans(16, .semibold)).monospacedDigit() }
                                else { Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)) }
                            }
                            .frame(width: 42, height: 42)
                            .foregroundStyle(item.selected ? LW.onInk : LW.ink)
                            .background(RoundedRectangle(cornerRadius: LW.R.xl, style: .continuous).fill(item.selected ? LW.ink : LW.wash(4)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(LWPress())
                        .accessibilityLabel(item.isOption ? "Iteration \(item.text)" : item.text)
                    }
                }
                .padding(12)
            }
        }
    }

    private func go() {
        if model.open(draft) {
            addressFocused = false
        } else {
            withAnimation(LW.easeOut) { invalid = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// A list row's press: the row tints with wash-4 while held.
struct LWRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? LW.wash(4) : .clear)
            .animation(LW.exit, value: configuration.isPressed)
    }
}

/// The kit's segmented control: a wash track, the chosen segment raised on `card` with the thumb shadow.
struct LWSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button { withAnimation(LW.easeOut(240)) { selection = value } } label: {
                    Text(label).font(LW.label)
                        .foregroundStyle(selection == value ? LW.ink : LW.muted)
                        .padding(.horizontal, 11).frame(height: 28)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: LW.R.chip - 1, style: .continuous).fill(LW.card)
                                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: LW.R.chip - 1, style: .continuous).strokeBorder(.black.opacity(0.04), lineWidth: 1))
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: LW.R.chip + 1, style: .continuous).fill(LW.wash(3)))
    }
}

/// Horizontal shake for an invalid URL.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
