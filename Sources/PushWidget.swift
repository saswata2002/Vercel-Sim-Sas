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
        VStack(alignment: .leading, spacing: 10) {
            header
            if hub.rooms.isEmpty {
                empty(
                    symbol: "dot.radiowaves.left.and.right",
                    text: "Join a room to receive links pushed from your browser.",
                    action: ("Set up", { model.pushJoinOpen = true })
                )
            } else if hub.received.isEmpty {
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

    private var invite: PushInvite? { PushHub.invite(from: link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header, as on the prototype menu's pages.
            VStack(alignment: .leading, spacing: 2) {
                Text("Join a room").font(LW.sans(22, .semibold)).foregroundStyle(LW.ink)
                Text("Links pushed to the room open on this phone.").font(LW.caption).foregroundStyle(LW.muted)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            // The room link: a pill like the menu's address bar.
            HStack(spacing: 0) {
                Image(systemName: "link").font(.system(size: 15, weight: .semibold)).foregroundStyle(LW.muted)
                    .frame(width: 44)
                TextField("", text: $link, prompt: Text("Room invite link").foregroundStyle(LW.muted))
                    .font(LW.body).foregroundStyle(LW.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($field, equals: .link)
                    .submitLabel(.next)
                    .onSubmit { field = .name }
                    .onChange(of: link) { invalid = false }
                Button {
                    if link.isEmpty { link = UIPasteboard.general.string ?? "" } else { link = "" }
                } label: {
                    Image(systemName: link.isEmpty ? "doc.on.clipboard" : "xmark")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(LW.ink)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 48, height: 52).contentShape(Rectangle())
                }
                .buttonStyle(LWPress())
                .accessibilityLabel(link.isEmpty ? "Paste" : "Clear link")
            }
            .frame(height: 52)
            .background(Capsule().fill(LW.card))
            .overlay(Capsule().strokeBorder(invalid ? LW.danger : field == .link ? LW.ink.opacity(0.6) : LW.line, lineWidth: 1))
            if invalid {
                Text("That isn\u{2019}t a room link. Copy it from Vercel Sim Push.")
                    .font(LW.caption).foregroundStyle(LW.danger).padding(.horizontal, 6)
                    .transition(.opacity)
            }

            // About this phone: icon rows, like the menu's.
            VStack(spacing: 0) {
                fieldRow("person", prompt: "Your name", text: $name, focus: .name, next: .device)
                fieldRow("iphone", prompt: hub.model, text: $device, focus: .device, next: nil)
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 18)).foregroundStyle(LW.ink).frame(width: 26)
                    Text("Platform").font(LW.body).foregroundStyle(LW.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(PushHub.platforms, id: \.self) { p in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(LW.easeOut) { platform = p }
                            } label: {
                                Image(systemName: p == "iOS" ? "apple.logo" : "smartphone")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(platform == p ? LW.ink : LW.muted)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(platform == p ? LW.wash(5) : .clear))
                            }
                            .buttonStyle(LWPress())
                            .accessibilityLabel(p)
                            .accessibilityAddTraits(platform == p ? .isSelected : [])
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 56)
            }

            Button("Join room", action: join)
                .buttonStyle(LWButton(variant: .primary, radius: 26, height: 52, fill: true))
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
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

    /// An icon row whose label is the field itself.
    private func fieldRow(_ symbol: String, prompt: String, text: Binding<String>, focus: Field, next: Field?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(LW.ink).frame(width: 26)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(LW.muted))
                .font(LW.body).foregroundStyle(LW.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($field, equals: focus)
                .submitLabel(next == nil ? .join : .next)
                .onSubmit { if let next { field = next } else { join() } }
            if !text.wrappedValue.isEmpty, field == focus {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(LW.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { field = focus }
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
