import SwiftUI

/// A saved link: every prototype opened from the link field is kept here automatically,
/// newest first, de-duplicated by host + path. The page's title is filled in once it loads;
/// a name you give it (Edit) wins over the page title and is never overwritten by it.
struct SavedLink: Codable, Identifiable, Equatable {
    var url: String
    var title: String?
    var savedAt: Date
    var name: String? = nil
    var id: String { url }

    /// What the row shows: your name, else the page's title, else the host.
    var label: String { name ?? title ?? host }
    var hasLabel: Bool { name != nil || title != nil }

    var host: String { URL(string: url)?.host ?? url }
    var path: String {
        guard let u = URL(string: url) else { return "" }
        return u.path == "/" ? "" : u.path
    }
}

@MainActor
final class LinkDirectory: ObservableObject {
    @Published private(set) var links: [SavedLink] = []
    private let key = "linkDirectory"
    private let limit = 50

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([SavedLink].self, from: data) {
            links = saved.filter { !Self.isFile($0.url) }
            for i in links.indices where links[i].title.map(Self.isErrorTitle) == true { links[i].title = nil }
            debugLog("directory: loaded \(links.count) [\(links.map(\.host).joined(separator: ", "))]")
        } else {
            // First run: start from the links already opened (minus local test servers).
            links = (UserDefaults.standard.stringArray(forKey: "recents") ?? [])
                .filter { !Self.isLocal($0) && !Self.isFile($0) }
                .map { SavedLink(url: $0, title: nil, savedAt: Date()) }
            persist()
        }
    }

    /// Called whenever a link is submitted. An existing entry keeps its place and title.
    func save(_ url: URL) {
        let raw = url.absoluteString
        if Self.isFile(raw) { return }
        if links.contains(where: { AppModel.sameDocument(URL(string: $0.url), url) }) { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            links.insert(SavedLink(url: raw, title: nil, savedAt: Date()), at: 0)
            if links.count > limit { links.removeLast(links.count - limit) }
        }
        persist()
    }

    /// The page's own title, once it has loaded ("noon — Home").
    func setTitle(_ title: String, for url: URL) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !Self.isErrorTitle(t), let i = links.firstIndex(where: { AppModel.sameDocument(URL(string: $0.url), url) }),
              links[i].title != t else { return }
        links[i].title = t
        persist()
    }

    /// Edit: a new name (empty = go back to the page's own title) and, if changed, a new URL.
    func update(_ link: SavedLink, name: String, url: URL) {
        guard let i = links.firstIndex(where: { $0.id == link.id }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var edited = links[i]
        edited.name = n.isEmpty ? nil : n
        if url.absoluteString != edited.url {
            // A different page: its old title no longer applies (it refills on next open).
            if !AppModel.sameDocument(URL(string: edited.url), url) { edited.title = nil }
            edited.url = url.absoluteString
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            links[i] = edited
            // Pointing it at a link that's already saved: keep just this one.
            links.removeAll { $0.id != edited.id && AppModel.sameDocument(URL(string: $0.url), url) }
        }
        debugLog("directory: edited \(link.url) → \(edited.url) name=\(edited.name ?? "nil")")
        persist()
    }

    func remove(_ link: SavedLink) {
        debugLog("directory: removed \(link.url)")
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { links.removeAll { $0.id == link.id } }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) { UserDefaults.standard.set(data, forKey: key) }
        debugLog("directory: saved \(links.count)")
    }

    /// Pages only: direct links to files (images, video, PDFs…) aren't prototypes.
    static func isFile(_ raw: String) -> Bool {
        let ext = (URL(string: raw)?.pathExtension ?? "").lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "mp4", "mov", "webm", "pdf", "json", "txt", "zip", "ico"].contains(ext)
    }

    /// Error pages ("404: NOT_FOUND", "500: INTERNAL_SERVER_ERROR", "Page not found") aren't
    /// a name for the link.
    static func isErrorTitle(_ t: String) -> Bool {
        t.range(of: #"^\s*[45]\d\d\b|^\s*(page )?not found\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isLocal(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return true }
        return host == "localhost" || host.hasPrefix("127.") || host == "[::1]" || host.hasSuffix(".local")
    }
}

/// The "Link Directory" card on the lock screen, under "Open a prototype".
struct LinkDirectoryWidget: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var directory: LinkDirectory
    /// The one row currently swiped open to show Delete or Edit (like Mail / Messages).
    @State private var openRow: String?
    /// Scroll position, for the edge feathers: the list's frame in the scroll view's space.
    @State private var content: CGRect = .zero
    @State private var viewport: CGFloat = 0
    private static let feather: CGFloat = 28

    /// 0…1: how much is hidden past each edge (fades in over the first 20 pt of scroll).
    private var topFade: CGFloat { min(max(-content.minY / 20, 0), 1) }
    private var bottomFade: CGFloat { viewport > 0 ? min(max((content.maxY - viewport) / 20, 0), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Link Directory").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                // How many are saved; rolls to the new number as links are added or deleted.
                if !directory.links.isEmpty {
                    Text("\(directory.links.count) \(directory.links.count == 1 ? "link" : "links")")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .contentTransition(.numericText(value: Double(directory.links.count)))
                        .animation(.snappy, value: directory.links.count)
                        .accessibilityLabel("\(directory.links.count) saved")
                }
            }

            if directory.links.isEmpty {
                LinkDirectoryEmpty()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(directory.links.enumerated()), id: \.element.id) { index, link in
                            if index > 0 { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5).padding(.leading, 44) }
                            LinkRow(link: link, openRow: $openRow, open: { model.open(link.url) },
                                    edit: { model.editingLink = link }, remove: { directory.remove(link) })
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("ldScroll")) }) { content = $0 }
                }
                .coordinateSpace(.named("ldScroll"))
                // Hug the rows when they fit; otherwise take the space offered and scroll.
                .frame(maxHeight: content.height > 0 ? content.height : nil)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
                // Rows feather out at the edges they scroll under instead of being cut off;
                // each edge only fades while there's more list beyond it.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(1 - topFade), .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.feather)
                        Rectangle()
                        LinearGradient(colors: [.black, .black.opacity(1 - bottomFade)], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.feather)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                // Newest first, so start at the top. Without this the list opened scrolled to
                // the end, because the card resizes once the safe area arrives at launch.
                .defaultScrollAnchor(.top)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

/// A saved link. Tap opens it. Swipe left reveals Delete (a long swipe deletes straight
/// away); swipe right reveals Edit (a long swipe opens the editor). Press and hold gives
/// Edit / Copy Link / Remove.
private struct LinkRow: View {
    let link: SavedLink
    @Binding var openRow: String?
    let open: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    @State private var offset: CGFloat = 0
    @State private var dragging = false
    @State private var flash = false

    private static let reveal: CGFloat = 76        // width of the Delete / Edit button
    private static let fullSwipe: CGFloat = 0.62   // fraction of the row width that deletes on release
    private static let fullEdit: CGFloat = 0.5     // …and that opens the editor (nothing to lose)
    private let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)

    var body: some View {
        ZStack {
            // Behind the row: Edit on the leading edge, Delete on the trailing one, each
            // growing with the swipe.
            if offset > 0 {
                Button { startEdit() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil").font(.system(size: 14, weight: .semibold))
                        if offset > 96 { Text("Edit").font(.system(size: 14, weight: .semibold)) }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .frame(width: max(offset - 6, 0), height: 44)
                    .modifier(LiquidGlassAction(tint: LiquidGlassAction.blue))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit")
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            if offset < 0 {
                Button(role: .destructive) { delete() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill").font(.system(size: 13, weight: .semibold))
                        if -offset > 96 { Text("Delete").font(.system(size: 14, weight: .semibold)) }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .frame(width: max(-offset - 6, 0), height: 44)
                    .modifier(LiquidGlassAction(tint: LiquidGlassAction.red))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.opacity)
            }

            content
                .offset(x: offset)
                // Feather the edge the row slides under, instead of a hard cut. The mask
                // sits in the row's own (unmoved) frame; it grows in with the swipe.
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(0, min(-offset * 0.4, 28)))
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(0, min(offset * 0.4, 28)))
                    }
                }
                .opacity(flash ? 0.55 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if offset != 0 { close(); return }      // a tap on an open row just closes it
            if openRow != nil { openRow = nil; return }
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.easeOut(duration: 0.15)) { flash = false } }
            open()
        }
        // Simultaneous, and horizontal-only, so vertical drags still scroll the list.
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    guard dragging || abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                    if !dragging { dragging = true; openRow = link.id }
                    let x = restOffset + v.translation.width
                    // Gentle resistance past either button.
                    offset = abs(x) <= Self.reveal ? x : (x > 0 ? 1 : -1) * (Self.reveal + (abs(x) - Self.reveal) * 0.9)
                    let armed = offset > rowWidth * Self.fullEdit
                    if armed != editArmed { editArmed = armed; if armed { UISelectionFeedbackGenerator().selectionChanged() } }
                }
                .onEnded { v in
                    guard dragging else { return }
                    dragging = false
                    editArmed = false
                    let width = rowWidth
                    let predicted = v.predictedEndTranslation.width + restOffset
                    if offset < 0 {
                        // Delete only on a deliberate long swipe: well past the button, or a fling
                        // that started past it. A quick short flick just shows Delete.
                        if -offset > width * Self.fullSwipe || (-offset > Self.reveal + 40 && predicted < -width * 1.1) {
                            delete()
                        } else if offset < -Self.reveal / 2 || v.predictedEndTranslation.width < -120 {
                            settle(at: -Self.reveal)
                        } else {
                            close()
                        }
                    } else if offset > width * Self.fullEdit {
                        startEdit()
                    } else if offset > Self.reveal / 2 || v.predictedEndTranslation.width > 120 {
                        settle(at: Self.reveal)
                    } else {
                        close()
                    }
                }
        )
        .background(GeometryReader { g in Color.clear.onAppear { rowWidth = g.size.width }.onChange(of: g.size.width) { _, w in rowWidth = w } })
        .onChange(of: openRow) { _, id in if id != link.id, offset != 0 { close() } }
        .contextMenu {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }
            Button { UIPasteboard.general.string = link.url } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(link.label), \(link.host + link.path)")
        .accessibilityAction(named: "Edit") { edit() }
        .accessibilityAction(named: "Delete") { remove() }
    }

    /// Where the row rests: 0, or swiped open to show Delete (−) or Edit (+).
    @State private var restOffset: CGFloat = 0
    @State private var editArmed = false
    @State private var rowWidth: CGFloat = 320

    private var content: some View {
        HStack(spacing: 12) {
            Text(String(link.host.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(link.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                // Second line only when it adds something: the address under a title,
                // or the path under a bare host.
                if let detail = link.hasLabel ? link.host + link.path : (link.path.isEmpty ? nil : link.path) {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func close() {
        restOffset = 0
        withAnimation(spring) { offset = 0 }
        if openRow == link.id { openRow = nil }
    }

    private func settle(at x: CGFloat) {
        withAnimation(spring) { offset = x }
        restOffset = x
        openRow = link.id
    }

    /// Edit: the row springs home as the editor comes up.
    private func startEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        close()
        edit()
    }

    private func delete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.18)) { offset = -rowWidth - 20 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            if openRow == link.id { openRow = nil }
            remove()
        }
    }
}

/// Tinted Liquid Glass for the swipe actions: the system material on iOS 26 (it refracts
/// the wallpaper and reacts to touch), and a close hand-built version on earlier iOS.
private struct LiquidGlassAction: ViewModifier {
    static let red = Color(red: 1, green: 0.27, blue: 0.23)
    static let blue = Color(red: 0.16, green: 0.52, blue: 1)
    let tint: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .contentShape(Capsule())
                .glassEffect(.regular.tint(tint.opacity(0.48)).interactive(), in: Capsule())
                .overlay {
                    // Rim light and a soft top sheen, so it reads as a lens even on a flat card.
                    ZStack {
                        Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.28)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.26), .clear], startPoint: .top, endPoint: .center))
                            .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 22)
                            .blur(radius: 1.5)
                    }
                    .allowsHitTesting(false)
                }
                .shadow(color: tint.opacity(0.3), radius: 10, y: 4)
        } else {
            content
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(tint.opacity(0.55))
                        // Specular highlight along the top, fading down.
                        Capsule().fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.04), .clear],
                                                      startPoint: .top, endPoint: .center))
                            .padding(1)
                        // Bright rim, stronger at the top-left like light on a lens.
                        Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.12), .white.opacity(0.35)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                    .shadow(color: tint.opacity(0.35), radius: 8, y: 3)
                }
                .environment(\.colorScheme, .dark)
        }
    }
}

private struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Edit a saved link: its name (empty = use the page's own title) and, only if you change
/// it, its URL. A small sheet over the lock screen; Save writes back to the directory.
struct LinkEditor: View {
    let link: SavedLink
    let save: (String, URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    @FocusState private var field: Field?
    private enum Field { case name, url }

    init(link: SavedLink, save: @escaping (String, URL) -> Void) {
        self.link = link
        self.save = save
        _name = State(initialValue: link.name ?? link.title ?? "")
        _url = State(initialValue: link.url)
    }

    private var parsed: URL? { AppModel.normalize(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("Edit Link").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Save") { commit() }
                    .font(.system(size: 17, weight: .semibold))
                    .disabled(parsed == nil)
            }
            .font(.system(size: 17))

            VStack(alignment: .leading, spacing: 10) {
                fieldRow("Name") {
                    TextField(link.title ?? link.host, text: $name)
                        .focused($field, equals: .name)
                        .submitLabel(.done)
                        .onSubmit(commit)
                    if !name.isEmpty {
                        Button { name = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.45)) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear name")
                    }
                }
                fieldRow("URL") {
                    TextField("https://…", text: $url)
                        .focused($field, equals: .url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .foregroundStyle(parsed == nil ? Color(red: 1, green: 0.45, blue: 0.4) : .white.opacity(0.75))
                }
                Text(name.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "No name: the page's own title is shown."
                     : "The URL only changes if you edit it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(290)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { field = .name } }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, alignment: .leading)
            content()
        }
        .font(.system(size: 16))
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    private func commit() {
        guard let u = parsed else { return }
        // Untouched URL text stays exactly as saved (no re-normalising).
        let target = url == link.url ? (URL(string: link.url) ?? u) : u
        // A name equal to the page title isn't a rename.
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save(n == link.title && link.name == nil ? "" : n, target)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}

/// Nothing saved yet: a glass link badge, a short headline and where links come from.
private struct LinkDirectoryEmpty: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(.white.opacity(0.1))
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.2)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 48, height: 48)
            .padding(.bottom, 14)

            Text("No saved links yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 4)
            Text("Paste a Vercel link above. Prototypes you open are saved here.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }
}
