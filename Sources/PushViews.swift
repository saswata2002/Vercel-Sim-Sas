import SwiftUI

/// The card that drops in from the top when a link is pushed from the web (or a room is
/// joined). Over everything: the lock screen, a prototype and the floating sheets.
struct PushNoticeView: View {
    @ObservedObject var hub: PushHub
    let topInset: CGFloat
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if let n = hub.notice {
                card(n)
                    .id(n.id)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, max(topInset, 20) + 4)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: hub.notice?.id)
    }

    private func card(_ n: PushNotice) -> some View {
        HStack(spacing: 12) {
            if n.kind == .joined {
                LWIconTile(symbol: "checkmark", size: 38)
            } else {
                LWLetterBadge(letter: String(n.title.prefix(1)).uppercased(), size: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(n.kind == .opening ? "OPENING" : n.kind == .saved ? "PUSHED TO YOU" : "PUSH FROM THE WEB")
                    .font(LW.micro).tracking(0.6).foregroundStyle(LW.muted)
                Text(n.title).font(LW.ui).foregroundStyle(LW.ink).lineLimit(1)
                Text(n.detail).font(LW.caption).foregroundStyle(LW.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            switch n.kind {
            case .saved:
                Button("Open") { hub.openNotice(n) }
                    .buttonStyle(LWButton(variant: .primary, radius: 16, height: 32))
            case .opening:
                ProgressView().controlSize(.small).tint(LW.muted).padding(.trailing, 6)
            case .joined:
                EmptyView()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LW.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LW.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 10)
        .offset(y: drag < 0 ? drag : drag * 0.25)
        .contentShape(Rectangle())
        .onTapGesture {
            if n.kind == .saved { hub.openNotice(n) } else { hub.notice = nil }
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -28 || v.predictedEndTranslation.height < -80 {
                        hub.notice = nil
                        drag = 0
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(n.kind == .saved ? .isButton : [])
    }
}

/// Options ▸ Push from the web: the rooms this iPhone is in, and its name there.
struct PushRoomRows: View {
    @ObservedObject var hub: PushHub
    @FocusState private var nameFocused: Bool

    var body: some View {
        if hub.rooms.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                LWIconTile(symbol: "qrcode.viewfinder", size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not in a room yet").font(LW.ui).foregroundStyle(LW.ink)
                    Text("Open Vercel Sim Push on a computer and scan its code with the iPhone Camera. Links pushed there open here.")
                        .font(LW.caption).foregroundStyle(LW.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        } else {
            ForEach(Array(hub.rooms.enumerated()), id: \.element.id) { i, room in
                if i > 0 { LWHairline(inset: 56) }
                HStack(spacing: 12) {
                    LWLetterBadge(letter: String(room.name.prefix(1)).uppercased(), size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(room.name).font(LW.ui).foregroundStyle(LW.ink).lineLimit(1)
                        status(hub.links[room.secret] ?? .offline)
                    }
                    Spacer(minLength: 8)
                    Button("Leave") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(LW.easeOut(220)) { hub.leave(room) }
                    }
                    .buttonStyle(LWButton(variant: .ghost, radius: 12, height: 32))
                }
                .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 56)
            }
        }
        LWHairline()
        HStack(spacing: 12) {
            Text("Name on the web").font(LW.ui).foregroundStyle(LW.ink)
            Spacer(minLength: 8)
            TextField("", text: $hub.deviceName, prompt: Text(hub.model).foregroundStyle(LW.muted))
                .font(LW.sans(14))
                .foregroundStyle(LW.ink)
                .tint(LW.ink)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }
                .frame(maxWidth: 190)
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
    }

    private func status(_ link: PushHub.Link) -> some View {
        let (text, color): (String, Color) = switch link {
        case .live: ("Live: pushes open here", LW.open)
        case .connecting: ("Connecting…", LW.muted)
        case .offline: ("Offline, retrying", LW.muted)
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(LW.caption).foregroundStyle(LW.muted)
        }
    }
}
