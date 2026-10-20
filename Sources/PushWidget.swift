import SwiftUI

/// Lock-screen card under the Link Directory: links pushed from the web page (Vercel Sim
/// Push), newest first, with who sent them and when. Tap one to open it. With no room
/// joined it says how to start; it shrinks to the latest push when the screen is short.
struct PushWidget: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var hub: PushHub
    /// The Link Directory card's height: the empty widget matches it.
    var matchHeight: CGFloat? = nil
    /// Set when this renders the page's list inside the morph (the morph's progress).
    var listProgress: CGFloat? = nil
    /// The height the page gives the list (to centre the empty state).
    var listHeight: CGFloat = 0
    private static var maxRows: Int { LinkDirectoryWidget.homeRows }   // like the Link Directory
    /// The room the list is filtered to (its secret); nil = every room.
    @State private var roomFilter: String?

    private var multiRoom: Bool { hub.rooms.count >= 2 }
    private var shown: [PushedLink] {
        guard let id = roomFilter, multiRoom, false else { return hub.received }
        return hub.received.filter { $0.roomID == id || ($0.roomID == nil && $0.room == hub.rooms.first { $0.secret == id }?.name) }
    }

    var body: some View {
        if let progress = listProgress {
            pageList(progress)
        } else {
            widget
        }
    }

    private var widget: some View {
        // Up to 3 links (2 on short screens), like the Link Directory.
        card(rows: Self.maxRows)
        #if DEBUG
        // Testing: -pushRoom N opens the card filtered to room N (0-based).
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-pushRoom"), i + 1 < args.count, let n = Int(args[i + 1]), hub.rooms.indices.contains(n) {
                roomFilter = hub.rooms[n].secret
            }
        }
        #endif
    }

    private func card(rows: Int) -> some View {
        Group {
            if hub.rooms.isEmpty { joinWidget(compact: rows == 0) } else { roomCard(rows: rows) }
        }
    }

    /// No room yet: just the call to action, a full-width pill that opens Join a room.
    /// No room yet: a widget like the Link Directory (title, then a dashed empty state with a
    /// Join button), as tall as the Link Directory card so the two sit as a pair. On a short
    /// screen (`compact`) just the title and the button.
    private func joinWidget(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if compact {
                joinButton
            } else {
                joinWell
            }
        }
        .padding(16)
        // As tall as the Link Directory card (measured), never shorter than its content.
        .frame(maxWidth: .infinity, minHeight: compact ? nil : matchHeight, alignment: .top)
        .lwSurface(radius: LW.R.sheet)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var joinWell: some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); model.pushJoinOpen = true } label: {
            VStack(spacing: 0) {
                if LinkDirectoryWidget.homeRows == 3 {      // no icon on short screens, like the directory's
                    LWIconTile(symbol: "dot.radiowaves.left.and.right", size: 36)
                        .padding(.bottom, 10)
                }
                Text("No rooms yet")
                    .font(LW.sans(15, .semibold))
                    .foregroundStyle(LW.ink)
                    .padding(.bottom, 14)
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("Join room").font(LW.ui)
                }
                .foregroundStyle(LW.onInk)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Capsule().fill(LW.ink))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous).fill(LW.wash(1)))
            .overlay(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous).strokeBorder(LW.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous))
        }
        .buttonStyle(LWPress())
        .accessibilityLabel("No rooms yet. Join room")
    }

    private var joinButton: some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); model.pushJoinOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                Text("Join a room").font(LW.ui)
            }
            .foregroundStyle(LW.onInk)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(LW.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(LWPress())
        .accessibilityLabel("Join a room to get links pushed from your browser")
    }

    /// The page: room chips (with join), every pushed link (the widget's two stay put, the
    /// rest fade in), or the empty state with the Join button.
    private func pageList(_ p: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if hub.rooms.isEmpty {
                // The dashed well grows with the morph to fill the page, its content centred.
                joinWell
                    .frame(maxWidth: .infinity, minHeight: max(listHeight, (matchHeight ?? 0) - 70))
            } else {
                if shown.isEmpty {
                    empty(symbol: "tray", text: roomFilter == nil || !multiRoom ? "Links pushed from the web will appear here." : "Nothing pushed to this room yet.", action: nil)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, link in
                            if i > 0 { LWHairline(inset: 44) }
                            row(link, copy: Double(fadeIn(p))).opacity(i < Self.maxRows ? 1 : Double(fadeIn(p)))
                        }
                    }
                }

            }
        }
    }

    private func roomCard(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if shown.isEmpty {
                empty(symbol: "tray", text: roomFilter == nil || !multiRoom ? "Links pushed from the web will appear here." : "Nothing pushed to this room yet.", action: nil)
            } else if rows > 0 {
                VStack(spacing: 0) {
                    ForEach(Array(shown.prefix(rows).enumerated()), id: \.element.id) { i, link in
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

    /// The header opens the full page (title, count, chevron); "+ Join" sits beside the chevron
    /// as its own button once a room is joined.
    private var header: some View {
        HStack(spacing: 8) {
            Button(action: openPage) {
                HStack(spacing: 8) {
                    Text("Shared with you").font(LW.title).foregroundStyle(LW.ink)
                        .lineLimit(1).fixedSize()
                    if !hub.received.isEmpty { LWCountPill(text: "\(hub.received.count)") }
                    Spacer(minLength: 8)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(LWPress())
            .accessibilityLabel("Shared with you. Show all")
            if !hub.rooms.isEmpty { PushPageJoin(height: 28) }
            Button(action: openPage) { WidgetChevron().contentShape(Circle()) }
                .buttonStyle(LWPress())
                .accessibilityLabel("Show all")
        }
    }

    private func openPage() {
        UISelectionFeedbackGenerator().selectionChanged()
        model.pushPageOpen = true
    }

    /// `copy`: the copy button's visibility (page only, fading in with the morph); nil on the widget.
    private func row(_ link: PushedLink, copy: Double? = nil) -> some View {
        HStack(spacing: 8) {
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
                }
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(LWPress())
            .accessibilityLabel("\(link.title ?? AppModel.display(link.url)), \(subtitle(link))")
            // Copy the link without opening it (on the full page only).
            if let copy {
                CopyLinkButton(url: link.url).opacity(copy).allowsHitTesting(copy > 0.99)
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = link.url } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            Button(role: .destructive) { hub.clearReceived() } label: { Label("Clear pushed links", systemImage: "trash") }
        }
    }

    private func subtitle(_ link: PushedLink) -> String {
        let who = link.from.map { "From \($0)" } ?? AppModel.display(link.url)
        // Under "All" with several rooms, say which room it came from.
        if multiRoom, roomFilter == nil, let room = roomName(link) { return "\(who) · \(room)" }
        return who
    }

    private func roomName(_ link: PushedLink) -> String? {
        if let id = link.roomID, let r = hub.rooms.first(where: { $0.secret == id }) { return r.name }
        return link.room
    }

    private func count(in room: PushRoom) -> Int {
        hub.received.filter { $0.roomID == room.secret || ($0.roomID == nil && $0.room == room.name) }.count
    }

    /// Two or more rooms: All, one chip per room (its own live dot and count), and join.
    private var roomChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "All", count: hub.received.count, dot: nil, selected: roomFilter == nil) { roomFilter = nil }
                ForEach(hub.rooms) { room in
                    chip(title: room.name, count: count(in: room), dot: hub.links[room.secret] ?? .offline,
                         selected: roomFilter == room.secret) { roomFilter = room.secret }
                        .contextMenu {
                            Button(role: .destructive) {
                                if roomFilter == room.secret { roomFilter = nil }
                                withAnimation(LW.easeOut) { hub.leave(room) }
                            } label: { Label("Leave \(room.name)", systemImage: "rectangle.portrait.and.arrow.right") }
                        }
                }
                Button { model.pushJoinOpen = true } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(LW.muted)
                        .frame(width: 32, height: 32)
                        .background(Circle().strokeBorder(LW.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                .buttonStyle(LWPress())
                .accessibilityLabel("Join another room")
            }
        }
        .animation(LW.easeOut, value: roomFilter)
    }

    private func chip(title: String, count: Int, dot: PushHub.Link?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(LW.easeOut) { action() }
        } label: {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot == .live ? LW.open : LW.muted.opacity(dot == .connecting ? 0.9 : 0.5)).frame(width: 6, height: 6)
                }
                Text(title).font(LW.sans(13, .medium)).lineLimit(1)
                if count > 0 {
                    Text("\(count)").font(LW.micro).monospacedDigit()
                        .foregroundStyle(selected ? LW.onInk.opacity(0.7) : LW.muted)
                }
            }
            .foregroundStyle(selected ? LW.onInk : LW.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(selected ? LW.ink : LW.wash(4)))
        }
        .buttonStyle(LWPress())
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        VStack(alignment: .leading, spacing: 16) {
            // Header: one line, icon and title.
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(LW.ink)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LW.wash(4)))
                Text("Join a room").font(LW.sans(20, .semibold)).foregroundStyle(LW.ink)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)  // icon lines up with the link row's

            // One grouped card: the link, then how this phone appears on the web.
            VStack(spacing: 0) {
                groupRow("link", focused: field == .link, invalid: invalid) {
                    TextField("", text: $link, prompt: Text("Paste the room link").foregroundStyle(LW.muted))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .link)
                        .submitLabel(.join)
                        .onSubmit(join)
                        .onChange(of: link) { invalid = false }
                    if !link.isEmpty { clearButton { link = "" } }
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

            // Platform: two choice cards, built like the link row above.
            HStack(spacing: 10) {
                ForEach(PushHub.platforms, id: \.self) { p in platformCard(p) }
            }

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
            fillFromClipboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { field = .link }   // rises with the sheet
        }
    }

    /// The room link found on the clipboard, per copy (`changeCount`), so iOS isn't asked to
    /// "Allow Paste" again each time the sheet opens.
    private static var clipboardInvite: (count: Int, invite: String?)?

    /// A room link already on the clipboard fills in by itself. Its contents are only read
    /// when iOS says (without reading them, so without asking) that it holds a link.
    private func fillFromClipboard() {
        let pb = UIPasteboard.general
        let count = pb.changeCount
        if let cached = Self.clipboardInvite, cached.count == count {
            if let invite = cached.invite, link.isEmpty { link = invite }
            return
        }
        Self.clipboardInvite = (count, nil)
        let read = {
            guard let clip = pb.string, PushHub.invite(from: clip) != nil else { return }
            Self.clipboardInvite = (count, clip)
            if link.isEmpty { link = clip }
        }
        if pb.hasURLs { read(); return }                      // vercelsim://pair?… copied as a URL
        guard pb.hasStrings else { return }
        pb.detectPatterns(for: [\.probableWebURL]) { result in
            guard case .success(let found) = result, found.contains(\.probableWebURL) else { return }
            DispatchQueue.main.async(execute: read)
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

    /// One platform choice: icon tile, name, and a radio that fills when picked.
    private func platformCard(_ p: String) -> some View {
        let on = platform == p
        let shape = RoundedRectangle(cornerRadius: LWFloatingSheet<EmptyView>.innerRadius, style: .continuous)
        return Button {
            guard !on else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(duration: 0.32, bounce: 0.18)) { platform = p }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: p == "iOS" ? "apple.logo" : "smartphone")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? LW.onInk : LW.muted)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? LW.ink : LW.wash(3)))
                Text(p).font(LW.ui).foregroundStyle(on ? LW.ink : LW.muted)
                    .lineLimit(1).minimumScaleFactor(0.85)   // narrow phones (SE): never "Androi / d"
                    .layoutPriority(1)
                Spacer(minLength: 0)
                ZStack {
                    Circle().strokeBorder(on ? LW.ink : LW.line, lineWidth: on ? 0 : 1.5)
                    Circle().fill(LW.ink).scaleEffect(on ? 1 : 0.2).opacity(on ? 1 : 0)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LW.onInk).scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
                }
                .frame(width: 18, height: 18)
            }
            .padding(.leading, 12).padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(shape.fill(on ? LW.raised : LW.card))
            .overlay(shape.strokeBorder(on ? LW.ink.opacity(0.5) : LW.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(LWPress())
        .accessibilityLabel(p)
        .accessibilityAddTraits(on ? .isSelected : [])
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
        // Name and device aren't asked for here any more; the phone keeps its current ones.
        hub.platform = platform
        hub.join(invite)
        field = nil
        dismiss()
    }
}

/// The widget header's trailing bits as the morph draws them: "+ Join" (with a room) and the chevron.
struct PushAccessory: View {
    @ObservedObject var hub: PushHub
    var body: some View {
        HStack(spacing: 8) {
            if !hub.rooms.isEmpty { PushPageJoin(height: 28).allowsHitTesting(false) }
            WidgetChevron()
        }
    }
}

/// Pushed from web's morph into its page.
struct PushMorph: View {
    @ObservedObject var hub: PushHub
    var progress: CGFloat
    let from: CGRect
    let screen: CGSize
    let top: CGFloat
    let margin: CGFloat
    let matchHeight: CGFloat?
    let onBack: () -> Void

    var body: some View {
        CardMorph(progress: progress, from: from, screen: screen, top: top, margin: margin,
                  title: "Shared with you", count: hub.received.count, onBack: onBack) {
            PushAccessory(hub: hub)
        } pageAction: {
            // Join another room, top right (the empty state has its own button).
            if !hub.rooms.isEmpty { PushPageJoin() }
        } rows: { p, available in
            PushWidget(hub: hub, matchHeight: matchHeight, listProgress: p, listHeight: available)
        }
    }
}

/// "+ Join" at the top right of the Shared with you page and on the widget header.
struct PushPageJoin: View {
    @EnvironmentObject private var model: AppModel
    /// 34 on the page; 28 on the widget, the chevron's size.
    var height: CGFloat = 34
    var body: some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); model.pushJoinOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                Text("Join").font(height < 34 ? LW.label : LW.ui)
            }
            .fixedSize()
            .foregroundStyle(LW.ink)
            .padding(.horizontal, height < 34 ? 11 : 14)
            .frame(height: height)
            .background(Capsule().fill(LW.wash(5)))
            .contentShape(Capsule())
        }
        .buttonStyle(LWPress())
        .accessibilityLabel("Join another room")
    }
}

/// A round copy button at the end of a row: copies the link and briefly turns into a tick.
struct CopyLinkButton: View {
    let url: String
    @State private var copied = false
    @State private var reset: DispatchWorkItem?

    var body: some View {
        Button {
            UIPasteboard.general.string = url
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(LW.easeOut(200)) { copied = true }
            reset?.cancel()
            let work = DispatchWorkItem { withAnimation(LW.easeOut(200)) { copied = false } }
            reset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(copied ? LW.ink : LW.muted)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Circle().fill(LW.wash(4)))
                .frame(width: 44, height: 52, alignment: .trailing)   // full-height tap target; lines up with the chevron
                .contentShape(Rectangle())
        }
        .buttonStyle(LWPress())
        .accessibilityLabel(copied ? "Copied" : "Copy link")
    }
}
