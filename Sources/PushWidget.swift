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
                    action: ("Set up", { model.panelOpen = true })
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
