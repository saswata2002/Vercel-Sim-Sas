import SwiftUI
import UIKit

/// Options over a running prototype, laid out like a mobile browser's page menu: the
/// prototype's iterations, four action tiles, and a short list of icon rows. Everything fits
/// without scrolling; Settings, Recents and Push open as pages inside the same sheet.
struct PrototypeMenu: View {
    @EnvironmentObject private var model: AppModel
    private enum Page: Hashable { case main, settings, recents, push }
    @State private var page = Page.main

    private let pad = LWFloatingSheet<EmptyView>.pad

    /// The push between pages: one spring for the slide and the sheet's height together.
    private static let push = Animation.spring(response: 0.4, dampingFraction: 1)
    /// Every page's height, measured off screen, so the sheet resizes during the slide
    /// rather than after it.
    @State private var heights: [Page: CGFloat] = [:]
    /// True while going deeper (the new page comes from the right).
    @State private var forward = true

    var body: some View {
        ZStack(alignment: .top) {
            // An in-sheet page change: the old page shifts a little and fades out softly while
            // the new one fades in from the other side; the sheet resizes in the same spring.
            pageView(page)
                .frame(maxWidth: .infinity, alignment: .top)
                .id(page)
                .transition(.asymmetric(
                    insertion: .modifier(active: PageFade(x: forward ? 24 : -24, shown: false),
                                         identity: PageFade(x: 0, shown: true)),
                    removal: .modifier(active: PageFade(x: forward ? -24 : 24, shown: false),
                                       identity: PageFade(x: 0, shown: true))))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Measure every page invisibly, at the sheet's width.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                ForEach([Page.main, .settings, .recents, .push], id: \.self) { p in
                    pageView(p)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                            heights[p] = h
                            if p == page { report(h, animated: model.menuHeight > 0) }
                        }
                }
            }
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        switch p {
        case .main: main
        case .settings: settings
        case .recents: recents
        case .push: push
        }
    }

    /// Go to a page: set the direction first, so the outgoing page leaves the right way.
    private func go(_ to: Page, back: Bool = false) {
        guard to != page else { return }
        forward = !back
        UISelectionFeedbackGenerator().selectionChanged()
        DispatchQueue.main.async {
            withAnimation(Self.push) {
                page = to
                if let h = heights[to] { model.menuHeight = h }
            }
        }
    }

    private func report(_ h: CGFloat, animated: Bool) {
        guard abs(h - model.menuHeight) > 0.5 else { return }
        if animated { withAnimation(Self.push) { model.menuHeight = h } } else { model.menuHeight = h }
    }

    // MARK: main page

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let switcher = model.switcher { iterations(switcher) }
            tiles
            VStack(spacing: 0) {
                checkRow("Status bar", symbol: "rectangle.topthird.inset.filled", isOn: $model.showStatusBar)
                checkRow("Haptics", symbol: "waveform", isOn: $model.hapticsOn)
                navRow("Settings", symbol: "gearshape") { go(.settings) }
            }
        }
        .padding(pad)
    }

    /// Home · Share.
    private var tiles: some View {
        HStack(spacing: 3) {
            tile("Home", symbol: "house") { model.goHome() }
            tile("Share", symbol: "square.and.arrow.up") { share() }
        }
        .clipShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous))
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(LW.ink)
                Text(title).font(LW.sans(12, .medium)).foregroundStyle(LW.ink).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(LW.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuTilePress())
    }

    /// The prototype's own picker: numbered iterations, then reset and named controls.
    /// The prototype's own picker: a capsule tray of pill chips, concentric (tray radius =
    /// chip radius + the 6 pt inset). The chips share the width when they fit. When there are
    /// more, the numbers scroll (snapping chip by chip, feathered where more are hidden,
    /// opened on the selected one) and reset stays pinned at the end.
    private func iterations(_ switcher: Switcher) -> some View {
        let all = switcher.items.filter { $0.kind != .action }
        let options = all.filter(\.isOption)
        let extras = all.filter { !$0.isOption }
        return ViewThatFits(in: .horizontal) {
            chipRow(all, flexible: true)
            HStack(spacing: 4) {
                IterationScroller(items: options, selected: options.first(where: \.selected)?.id) { item in chip(item, flexible: false) }
                ForEach(extras) { chip($0, flexible: false) }
            }
        }
        .padding(Self.trayInset)
        .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous).fill(LW.card))
        .clipShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous))
    }

    fileprivate static let trayInset: CGFloat = 6
    fileprivate static let chipHeight: CGFloat = 44

    private func chipRow(_ items: [Switcher.Item], flexible: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(items) { chip($0, flexible: flexible) }
        }
    }

    private func chip(_ item: Switcher.Item, flexible: Bool) -> some View {
        Button { model.press(item) } label: {
            Group {
                if item.isOption { Text(item.text).font(LW.sans(16, .semibold)).monospacedDigit() }
                else { Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold)) }
            }
            .foregroundStyle(item.selected ? LW.onInk : LW.ink)
            .frame(minWidth: Self.chipHeight, maxWidth: flexible ? .infinity : Self.chipHeight)
            .frame(height: Self.chipHeight)
            .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.nested(Self.trayInset), style: .continuous).fill(item.selected ? LW.ink : LW.wash(3)))
            .contentShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.nested(Self.trayInset), style: .continuous))
        }
        .buttonStyle(LWPress())
        .accessibilityLabel(item.isOption ? "Iteration \(item.text)" : item.text)
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }

    private func checkRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button { withAnimation(LW.easeOut) { isOn.wrappedValue.toggle() } } label: {
            HStack(spacing: 14) {
                rowIcon(symbol)
                Text(title).font(LW.body).foregroundStyle(LW.ink)
                Spacer()
                MenuCheckbox(on: isOn.wrappedValue)
            }
            .padding(.horizontal, 6).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(LWRowPress())
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    private func navRow(_ title: String, symbol: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                rowIcon(symbol)
                Text(title).font(LW.body).foregroundStyle(LW.ink)
                Spacer()
                if let detail { Text(detail).font(LW.sans(13)).foregroundStyle(LW.muted) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(LW.muted.opacity(0.7))
            }
            .padding(.horizontal, 6).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(LWRowPress())
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(LW.ink).frame(width: 26)
    }

    // MARK: sub-pages

    private func pageHeader(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Button { go(.main, back: true) } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(LW.ink)
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(LWPress())
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LW.sans(22, .semibold)).foregroundStyle(LW.ink)
                Text(subtitle).font(LW.caption).foregroundStyle(LW.muted).lineLimit(1)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 4) {
            pageHeader("Settings", "\(model.currentURL?.host ?? "Prototype") on this iPhone")
            switchRow("Home indicator", symbol: "minus", isOn: $model.showHomeIndicator)
            switchRow("Scale 375 designs", symbol: "arrow.left.and.right.square", isOn: $model.fitBase)
            switchRow("Iteration pill on screen", symbol: "capsule.portrait", isOn: $model.showIterationPill)
        }
        .padding(pad)
    }

    private func switchRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 14) {
                rowIcon(symbol)
                Text(title).font(LW.body).foregroundStyle(LW.ink)
            }
        }
        .toggleStyle(LWSwitchStyle())
        .padding(.horizontal, 6)
        .frame(minHeight: 56)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 4) {
            pageHeader("Recents", "Prototypes opened on this iPhone")
            if model.recents.isEmpty {
                Text("Nothing yet.").font(LW.body).foregroundStyle(LW.muted).padding(.vertical, 12).padding(.horizontal, 6)
            }
            ForEach(Array(model.recents.prefix(6).enumerated()), id: \.element) { i, url in
                if i > 0 { LWHairline(inset: 52) }
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
                    .padding(.horizontal, 6).frame(minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(LWRowPress())
            }
        }
        .padding(pad)
    }

    private var push: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { go(.settings, back: true) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(LW.ink)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(LWPress())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push from the web").font(LW.sans(22, .semibold)).foregroundStyle(LW.ink)
                    Text("Links pushed from your browser open here").font(LW.caption).foregroundStyle(LW.muted)
                }
            }
            VStack(spacing: 0) { PushRoomRows(hub: model.push) }
                .lwSurface(radius: LWFloatingSheet<EmptyView>.innerRadius)
                .clipShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous))
        }
        .padding(pad)
    }

    // MARK: actions

    private func share() {
        guard let url = model.webView.url ?? model.currentURL else { return }
        model.panelOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let top = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
            var vc = top
            while let p = vc.presentedViewController { vc = p }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = vc.view
            vc.present(sheet, animated: true)
        }
    }
}

/// The browser-menu checkbox: a rounded square outline, ink with a tick when on.
private struct MenuCheckbox: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(on ? LW.ink : .clear)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? LW.ink : LW.muted, lineWidth: 1.6))
            .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(LW.onInk).opacity(on ? 1 : 0))
            .frame(width: 24, height: 24)
            .padding(.trailing, 8)
    }
}

/// A tile's press: tints a step brighter while held.
private struct MenuTilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(LW.wash(configuration.isPressed ? 4 : 0))
            .animation(LW.exit, value: configuration.isPressed)
    }
}

/// The numbered chips when they don't all fit: a snapping horizontal scroll that opens on the
/// selected chip and fades at whichever edge has more hidden.
private struct IterationScroller<Chip: View>: View {
    let items: [Switcher.Item]
    let selected: Int?
    @ViewBuilder let chip: (Switcher.Item) -> Chip
    @State private var offset: CGFloat = 0
    @State private var content: CGFloat = 0
    @State private var viewport: CGFloat = 0
    private let feather: CGFloat = 22

    private var leading: CGFloat { min(max(offset / 16, 0), 1) }
    private var trailing: CGFloat { min(max((content - viewport - offset) / 16, 0), 1) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items) { chip($0).id($0.id) }
                }
                .scrollTargetLayout()
                // The row's frame in the scroller's space: its x is minus the scroll offset.
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("iterScroll")) }) { r in
                    offset = -r.minX; content = r.width
                }
            }
            .coordinateSpace(.named("iterScroll"))
            .scrollTargetBehavior(.viewAligned)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { viewport = $0 }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(1 - leading), .black], startPoint: .leading, endPoint: .trailing).frame(width: feather)
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(1 - trailing)], startPoint: .leading, endPoint: .trailing).frame(width: feather)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.nested(6), style: .continuous))
            .onAppear {
                guard let selected else { return }
                DispatchQueue.main.async { proxy.scrollTo(selected, anchor: .center) }
            }
            .onChange(of: selected) { _, id in
                guard let id else { return }
                withAnimation(LW.easeOut(300)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// A page during a change: shifted by `x` points, and faded, softly blurred and a touch
/// smaller while not `shown`.
private struct PageFade: ViewModifier {
    let x: CGFloat
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
            .scaleEffect(shown ? 1 : 0.98, anchor: .top)
            .offset(x: x)
    }
}
