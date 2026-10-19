import SwiftUI

/// Lock-screen card under the Link Directory: links pushed from the web page (Vercel Sim
/// Push), newest first, with who sent them and when. Tap one to open it. With no room
/// joined it says how to start; it shrinks to the latest push when the screen is short.
struct PushWidget: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var hub: PushHub
    private static let maxRows = 2

    var body: some View {
        ViewThatFits(in: .vertical) {
            card(rows: Self.maxRows)
            card(rows: 1)
            card(rows: 0)
        }
    }

    private func card(rows: Int) -> some View {
        Group {
            if hub.rooms.isEmpty { joinCTA } else { roomCard(rows: rows) }
        }
    }

    /// No room yet: just the call to action, a full-width pill that opens Join a room.
    private var joinCTA: some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); model.pushJoinOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                Text("Join a room").font(LW.ui)
            }
            .foregroundStyle(LW.onInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(LW.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(LWPress())
        .accessibilityLabel("Join a room to get links pushed from your browser")
    }

    private func roomCard(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if hub.received.isEmpty {
                empty(symbol: "tray", text: "Links pushed from the web will appear here.", action: nil)
            } else if rows > 0 {
                VStack(spacing: 0) {
                    ForEach(Array(hub.received.prefix(rows).enumerated()), id: \.element.id) { i, link in
                        if i > 0 { LWHairline(inset: 44) }
                        row(link)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lwSurface(radius: LW.R.sheet)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Pushed from web").font(LW.title).foregroundStyle(LW.ink)
            if !hub.received.isEmpty {
                LWCountPill(text: "\(hub.received.count)")
            }
            Spacer(minLength: 8)
            if !hub.rooms.isEmpty {
                let connecting = !hub.isLive && hub.links.values.contains(.connecting)
                HStack(spacing: 5) {
                    Circle().fill(hub.isLive ? LW.open : LW.muted.opacity(connecting ? 0.9 : 0.6)).frame(width: 6, height: 6)
                    Text(hub.isLive ? "Live" : connecting ? "Connecting" : "Offline").font(LW.caption).foregroundStyle(LW.muted)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(LW.wash(4)))
                .animation(LW.easeOut, value: hub.isLive)
                .accessibilityLabel(hub.isLive ? "Connected" : connecting ? "Connecting" : "Offline")
            }
        }
    }

    private func row(_ link: PushedLink) -> some View {
        Button { model.open(link.url) } label: {
            HStack(spacing: 12) {
                LWLetterBadge(letter: String((link.title ?? URL(string: link.url)?.host ?? "?").prefix(1)).uppercased())
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title ?? AppModel.display(link.url))
                        .font(LW.bodyMedium).foregroundStyle(LW.ink).lineLimit(1)
                    Text(subtitle(link))
                        .font(LW.sans(13)).foregroundStyle(LW.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(LW.muted)
            }
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(LWPress())
        .contextMenu {
            Button { UIPasteboard.general.string = link.url } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            Button(role: .destructive) { hub.clearReceived() } label: { Label("Clear pushed links", systemImage: "trash") }
        }
        .accessibilityLabel("\(link.title ?? AppModel.display(link.url)), \(subtitle(link))")
    }

    private func subtitle(_ link: PushedLink) -> String {
        let who = link.from.map { "From \($0)" } ?? AppModel.display(link.url)
        return "\(who) · \(Self.ago(link.at))"
    }

    private func empty(symbol: String, text: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 12) {
            LWIconTile(symbol: symbol, size: 36)
            Text(text).font(LW.sans(13)).foregroundStyle(LW.muted).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(LWButton(variant: .soft, radius: LW.R.xl, height: 32))
            }
        }
    }

    /// "now", "4m", "2h", "3d".
    static func ago(_ date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        return "\(s / 86_400)d ago"
    }
}

/// Joining a push room from the lock screen: the room's invite link, how this phone is
/// named on the web, and one button.
struct PushJoinSheet: View {
    @ObservedObject var hub: PushHub
    @Environment(\.floatingDismiss) private var dismiss
    @State private var link = ""
    @State private var name = ""
    @State private var device = ""
    @State private var platform = "iOS"
    @State private var invalid = false
    @FocusState private var field: Field?
    private enum Field { case link, name, device }
    @Namespace private var platformNS

    private var invite: PushInvite? { PushHub.invite(from: link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: what this is, in one glance.
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(LW.ink)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: LW.R.control, style: .continuous).fill(LW.wash(4)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join a room").font(LW.sans(20, .semibold)).foregroundStyle(LW.ink)
                    Text("Links pushed to the room open on this phone.")
                        .font(LW.sans(13)).foregroundStyle(LW.muted).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }

            // One grouped card: the link, then how this phone appears on the web.
            VStack(spacing: 0) {
                groupRow("link", focused: field == .link, invalid: invalid) {
                    TextField("", text: $link, prompt: Text("Paste the room link").foregroundStyle(LW.muted))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .link)
                        .submitLabel(.next)
                        .onSubmit { field = .name }
                        .onChange(of: link) { invalid = false }
                    if link.isEmpty {
                        Button("Paste") { link = UIPasteboard.general.string ?? "" }
                            .font(LW.label).foregroundStyle(LW.ink)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.nested(13), style: .continuous).fill(LW.wash(5)))
                            .buttonStyle(LWPress())
                    } else {
                        clearButton { link = "" }
                    }
                }
                LWHairline(inset: 58)
                groupRow("person", focused: field == .name) {
                    TextField("", text: $name, prompt: Text("Your name").foregroundStyle(LW.muted))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($field, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { field = .device }
                    if !name.isEmpty, field == .name { clearButton { name = "" } }
                }
                LWHairline(inset: 58)
                groupRow(platform == "iOS" ? "iphone" : "smartphone", focused: field == .device) {
                    TextField("", text: $device, prompt: Text(hub.model).foregroundStyle(LW.muted))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($field, equals: .device)
                        .submitLabel(.join)
                        .onSubmit(join)
                    if !device.isEmpty, field == .device { clearButton { device = "" } }
                }
            }
            .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous).fill(LW.card))
            .overlay(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous)
                .strokeBorder(invalid ? LW.danger.opacity(0.7) : LW.line, lineWidth: 1))

            if invalid {
                Label("That isn\u{2019}t a room link. Copy it from Vercel Sim Push.", systemImage: "exclamationmark.circle")
                    .font(LW.caption).foregroundStyle(LW.danger)
                    .padding(.horizontal, 4).padding(.top, -6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Platform: a labelled segmented control.
            HStack(spacing: 4) {
                ForEach(PushHub.platforms, id: \.self) { p in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(LW.easeOut(240)) { platform = p }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: p == "iOS" ? "apple.logo" : "smartphone").font(.system(size: 14, weight: .semibold))
                            Text(p).font(LW.ui)
                        }
                        .foregroundStyle(platform == p ? LW.ink : LW.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if platform == p {
                                RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.nested(4), style: .continuous).fill(LW.raised).matchedGeometryEffect(id: "platform", in: platformNS)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(platform == p ? .isSelected : [])
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous).fill(LW.card))
            .overlay(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous).strokeBorder(LW.line, lineWidth: 1))

            // The one action: ink when ready, a quiet outline until there's a link.
            let ready = !link.trimmingCharacters(in: .whitespaces).isEmpty
            Button(action: join) {
                HStack(spacing: 8) {
                    Text("Join room").font(LW.ui)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(ready ? LW.onInk : LW.muted)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous).fill(ready ? LW.ink : LW.wash(3)))
                .overlay(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous).strokeBorder(ready ? .clear : LW.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous))
            }
            .buttonStyle(LWPress())
            .disabled(!ready)
            .animation(LW.easeOut, value: ready)
        }
        .animation(LW.easeOut, value: invalid)
        .padding(LWFloatingSheet<EmptyView>.pad)
        .padding(.top, 6)
        .tint(LW.ink)
        .environment(\.colorScheme, .dark)
        .onAppear {
            name = hub.deviceName == hub.model ? "" : hub.deviceName
            device = hub.deviceLabel
            platform = hub.platform
            // A room link already on the clipboard fills in by itself.
            if let clip = UIPasteboard.general.string, PushHub.invite(from: clip) != nil { link = clip }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { field = link.isEmpty ? .link : .name }
        }
    }

    /// A row of the grouped card: an icon tile that lights up while its field is active.
    private func groupRow<Content: View>(_ symbol: String, focused: Bool, invalid: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(invalid ? LW.danger : focused ? LW.ink : LW.muted)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.nested(12), style: .continuous).fill(focused ? LW.wash(5) : LW.wash(3)))
                .animation(LW.easeOut, value: focused)
            HStack(spacing: 6) { content() }
                .font(LW.body).foregroundStyle(LW.ink)
        }
        .padding(.leading, 14).padding(.trailing, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(LW.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear")
    }

    private func join() {
        guard let invite else {
            withAnimation(LW.easeOut) { invalid = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        hub.deviceName = n
        hub.deviceLabel = device.trimmingCharacters(in: .whitespacesAndNewlines)
        hub.platform = platform
        hub.join(invite)
        field = nil
        dismiss()
    }
}
