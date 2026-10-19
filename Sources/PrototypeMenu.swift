import SwiftUI
import UIKit

/// Options over a running prototype, laid out like a mobile browser's page menu: an address
/// pill (back, forward, address, copy, reload), the prototype's iterations, four action
/// tiles, and a short list of icon rows with inline controls. Everything fits
/// without scrolling; Settings, Recents and Push open as pages inside the same sheet.
struct PrototypeMenu: View {
    @EnvironmentObject private var model: AppModel
    private enum Page { case main, settings, recents, push }
    @State private var page = Page.main
    @State private var editing = false
    @State private var draft = ""
    @State private var invalid = false
    @State private var copied = false
    @FocusState private var addressFocused: Bool

    private let pad = LWFloatingSheet<EmptyView>.pad

    var body: some View {
        ZStack(alignment: .top) {
            switch page {
            case .main: main.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
            case .settings: settings.transition(.move(edge: .trailing).combined(with: .opacity))
            case .recents: recents.transition(.move(edge: .trailing).combined(with: .opacity))
            case .push: push.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: page)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: editing)
        .fixedSize(horizontal: false, vertical: true)
        // Report the height so the sheet is exactly this tall, following page changes.
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
            guard abs(h - model.menuHeight) > 0.5 else { return }
            if model.menuHeight == 0 { model.menuHeight = h }
            else { withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { model.menuHeight = h } }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    // MARK: main page

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            addressPill
            if editing {
                Text(invalid ? "That isn\u{2019}t a valid link." : "Paste or type a link, then Go.")
                    .font(LW.caption).foregroundStyle(invalid ? LW.danger : LW.muted)
                    .padding(.horizontal, 6)
            } else {
                if let switcher = model.switcher { iterations(switcher) }
                tiles
                VStack(spacing: 0) {
                    checkRow("Status bar", symbol: "rectangle.topthird.inset.filled", isOn: $model.showStatusBar)
                    checkRow("Haptics", symbol: "waveform", isOn: $model.hapticsOn)
                    navRow("Settings", symbol: "gearshape") { page = .settings }
                }
            }
        }
        .padding(pad)
    }

    /// Back · Forward · address · copy · reload, on one pill.
    private var addressPill: some View {
        HStack(spacing: 0) {
            if editing {
                Image(systemName: "link").font(.system(size: 14, weight: .medium)).foregroundStyle(LW.muted)
                    .frame(width: 40)
                TextField("", text: $draft, prompt: Text("Paste a Vercel link").foregroundStyle(LW.muted))
                    .font(LW.body).foregroundStyle(LW.ink).tint(LW.ink)
                    .keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go).focused($addressFocused)
                    .onSubmit(go)
                    .onChange(of: draft) { invalid = false }
                pillIcon("xmark", label: "Cancel") { stopEditing() }
                LWIconButton(symbol: "arrow.right", look: .solid, size: 36, action: go)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.trailing, 6)
                    .accessibilityLabel("Go")
            } else {
                pillIcon("chevron.left", label: "Back", enabled: model.canGoBack) { model.goBack(); model.panelOpen = false }
                pillIcon("chevron.right", label: "Forward", enabled: model.canGoForward) { model.goForward(); model.panelOpen = false }
                Button { startEditing() } label: {
                    Text(model.currentURL.map { AppModel.display(($0).absoluteString) } ?? "")
                        .font(LW.bodyMedium).foregroundStyle(LW.ink)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Address, \(model.currentURL.map { AppModel.display($0.absoluteString) } ?? ""). Edit")
                pillIcon(copied ? "checkmark" : "link", label: "Copy link") { copyLink() }
                pillIcon("arrow.clockwise", label: "Reload") { model.reload(); model.panelOpen = false }
            }
        }
        .frame(height: 52)
        .background(Capsule().fill(LW.card))
        .overlay(Capsule().strokeBorder(editing && addressFocused ? LW.ink.opacity(0.6) : LW.line, lineWidth: 1))
        .modifier(MenuShake(animatableData: invalid ? 1 : 0))
    }

    private func pillIcon(_ symbol: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? LW.ink : LW.muted.opacity(0.45))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(LWPress())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Home · Screenshot · Share · Recents.
    private var tiles: some View {
        HStack(spacing: 3) {
            tile("Home", symbol: "house") { model.goHome() }
            tile("Screenshot", symbol: "camera.viewfinder") { model.takeScreenshot() }
            tile("Share", symbol: "square.and.arrow.up") { share() }
            tile("Recents", symbol: "clock.arrow.circlepath") { page = .recents }
        }
        .clipShape(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous))
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
    private func iterations(_ switcher: Switcher) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(switcher.items.filter { $0.kind != .action }) { item in
                        Button { model.press(item) } label: {
                            Group {
                                if item.isOption { Text(item.text).font(LW.sans(16, .semibold)).monospacedDigit() }
                                else { Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)) }
                            }
                            .frame(width: 42, height: 42)
                            .foregroundStyle(item.selected ? LW.onInk : LW.ink)
                            .background(RoundedRectangle(cornerRadius: LW.R.xl, style: .continuous).fill(item.selected ? LW.ink : LW.wash(4)))
                        }
                        .buttonStyle(LWPress())
                        .accessibilityLabel(item.isOption ? "Iteration \(item.text)" : item.text)
                    }
                }
                .padding(10)
            }
            ForEach(switcher.items.filter { $0.kind == .action }) { item in
                LWHairline(inset: 48)
                navRow(item.text, symbol: item.symbol) { model.press(item); model.panelOpen = false }
            }
        }
        .lwSurface(radius: LW.R.tile)
        .clipShape(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous))
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
            Button { page = .main } label: {
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
            navRow("Push from the web", symbol: "dot.radiowaves.left.and.right",
                   detail: model.push.rooms.isEmpty ? "Off" : "\(model.push.rooms.count) room\(model.push.rooms.count == 1 ? "" : "s")") { page = .push }
            HStack {
                Spacer()
                Button { model.clearWebsiteData(); model.panelOpen = false } label: {
                    Text("Clear cookies & cache").font(LW.ui).foregroundStyle(LW.danger)
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(Capsule().fill(LW.danger.opacity(0.14)))
                }
                .buttonStyle(LWPress())
            }
            .padding(.top, 12)
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
                Button { page = .settings } label: {
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
                .lwSurface(radius: LW.R.tile)
                .clipShape(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous))
        }
        .padding(pad)
    }

    // MARK: actions

    private func startEditing() {
        draft = model.currentURL.map { AppModel.display($0.absoluteString) } ?? ""
        editing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { addressFocused = true }
    }

    private func stopEditing() {
        debugLog("menu: stop editing")
        addressFocused = false
        invalid = false
        editing = false
    }

    private func go() {
        if model.open(draft) {
            addressFocused = false
        } else {
            withAnimation(LW.easeOut) { invalid = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func copyLink() {
        guard let url = model.webView.url ?? model.currentURL else { return }
        UIPasteboard.general.string = url.absoluteString
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }

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

private struct MenuShake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
