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
    /// A real row's height (the lazy stack only estimates rows it hasn't laid out yet).
    @State private var rowHeight: CGFloat = 0
    private static let feather: CGFloat = 28
    /// At most this many rows show at once; more scroll inside the card.
    private static let visibleRows = 5

    /// The list's height: all rows while they fit, else exactly `visibleRows` of them.
    private var listHeight: CGFloat? {
        // From a real row's height: the lazy stack's own height is only an estimate for rows
        // it hasn't laid out, and lags when links are added, which cut the last row off.
        let rows = min(directory.links.count, Self.visibleRows)
        if rowHeight > 0, rows > 0 { return (rowHeight * CGFloat(rows) + CGFloat(rows - 1)).rounded() } // rows + hairlines
        return content.height > 0 ? content.height : nil
    }

    /// 0…1: how much is hidden past each edge (fades in over the first 20 pt of scroll).
    private var topFade: CGFloat { min(max(-content.minY / 20, 0), 1) }
    private var bottomFade: CGFloat { viewport > 0 ? min(max((content.maxY - viewport) / 20, 0), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Link Directory").font(LW.title).foregroundStyle(LW.ink)
                // How many are saved: the kit's count pill; rolls as links are added or deleted.
                if !directory.links.isEmpty {
                    LWCountPill(text: "\(directory.links.count)")
                        .contentTransition(.numericText(value: Double(directory.links.count)))
                        .animation(LW.easeOut(240), value: directory.links.count)
                        .accessibilityLabel("\(directory.links.count) saved")
                }
                Spacer(minLength: 8)
            }

            if directory.links.isEmpty {
                LinkDirectoryEmpty()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(directory.links.enumerated()), id: \.element.id) { index, link in
                            if index > 0 { LWHairline(inset: 44) }
                            LinkRow(link: link, openRow: $openRow, open: { model.open(link.url) },
                                    edit: { model.editingLink = link }, remove: { directory.remove(link) })
                                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in if index == 0 { rowHeight = h } }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("ldScroll")) }) { content = $0 }
                }
                .coordinateSpace(.named("ldScroll"))
                // Hug the rows up to five; past that (or when the screen is too short) scroll.
                .frame(maxHeight: listHeight)
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
        .lwSurface(radius: LW.R.sheet)
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
                        Image(systemName: "pencil").font(.system(size: 14, weight: .medium))
                        if offset > 96 { Text("Edit").font(LW.ui) }
                    }
                    .foregroundStyle(LW.ink)
                    .frame(width: max(offset - 6, 0), height: 44)
                    .modifier(LWSwipeAction(fill: LW.wash(4)))           // soft: a secondary action
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit")
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            if offset < 0 {
                Button(role: .destructive) { delete() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 14, weight: .medium))
                        if -offset > 96 { Text("Delete").font(LW.ui) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: max(-offset - 6, 0), height: 44)
                    .modifier(LWSwipeAction(fill: LW.dangerSolid))       // solid danger: it confirms the delete
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
        // Swipe: a horizontal-only pan. On iOS 18+ it's a UIKit recogniser that refuses to start
        // on vertical movement, so the list scrolls like a native one (a SwiftUI DragGesture on
        // scroll content competes with the scroll view and wins slow or diagonal drags).
        .modifier(RowSwipe(changed: dragChanged, ended: dragEnded))
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

    private func dragChanged(_ tx: CGFloat) {
        if !dragging { dragging = true; openRow = link.id }
        let x = restOffset + tx
        // Gentle resistance past either button.
        offset = abs(x) <= Self.reveal ? x : (x > 0 ? 1 : -1) * (Self.reveal + (abs(x) - Self.reveal) * 0.9)
        let armed = offset > rowWidth * Self.fullEdit
        if armed != editArmed { editArmed = armed; if armed { UISelectionFeedbackGenerator().selectionChanged() } }
    }

    /// `flung`: where the swipe would come to rest at its release speed (translation + momentum).
    private func dragEnded(_ tx: CGFloat, _ flung: CGFloat) {
        guard dragging else { return }
        dragging = false
        editArmed = false
        // Cancelled (see HorizontalPan): back to the rest position, no action.
        if tx.isNaN {
            if restOffset == 0 { close() } else { settle(at: restOffset) }
            return
        }
        let width = rowWidth
        let predicted = flung + restOffset
        if offset < 0 {
            // Delete only on a deliberate long swipe: well past the button, or a fling
            // that started past it. A quick short flick just shows Delete.
            if -offset > width * Self.fullSwipe || (-offset > Self.reveal + 40 && predicted < -width * 1.1) {
                delete()
            } else if offset < -Self.reveal / 2 || flung < -120 {
                settle(at: -Self.reveal)
            } else {
                close()
            }
        } else if offset > width * Self.fullEdit {
            startEdit()
        } else if offset > Self.reveal / 2 || flung > 120 {
            settle(at: Self.reveal)
        } else {
            close()
        }
    }

    /// Where the row rests: 0, or swiped open to show Delete (−) or Edit (+).
    @State private var restOffset: CGFloat = 0
    @State private var editArmed = false
    @State private var rowWidth: CGFloat = 320

    private var content: some View {
        HStack(spacing: 12) {
            LWLetterBadge(letter: String(link.host.prefix(1)).uppercased())
            VStack(alignment: .leading, spacing: 2) {
                Text(link.label)
                    .font(LW.bodyMedium)
                    .foregroundStyle(LW.ink)
                    .lineLimit(1)
                // Second line only when it adds something: the address under a title,
                // or the path under a bare host.
                if let detail = link.hasLabel ? link.host + link.path : (link.path.isEmpty ? nil : link.path) {
                    Text(detail)
                        .font(LW.sans(13))
                        .foregroundStyle(LW.muted)
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

/// A swipe action in the kit's button shape: `control` radius, flat fill, no glass or shadow.
private struct LWSwipeAction: ViewModifier {
    let fill: Color
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LW.R.control, style: .continuous)
        content.background(shape.fill(fill)).contentShape(shape)
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
    @Environment(\.floatingDismiss) private var dismiss
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit link").font(LW.title).foregroundStyle(LW.ink)
                Text("Rename it, or point it at a different URL.").font(LW.sans(14)).foregroundStyle(LW.muted)
            }

            // The kit's inputs: label above, hint below; an error replaces the hint.
            VStack(alignment: .leading, spacing: 14) {
                field("Name", hint: name.trimmingCharacters(in: .whitespaces).isEmpty ? "No name: the page\u{2019}s own title is shown." : nil, focused: field == .name) {
                    TextField("", text: $name, prompt: Text(link.title ?? link.host).foregroundStyle(LW.muted))
                        .focused($field, equals: .name)
                        .submitLabel(.done)
                        .onSubmit(commit)
                    if !name.isEmpty {
                        LWIconButton(symbol: "xmark", look: .ghost, size: 26) { name = "" }
                            .accessibilityLabel("Clear name")
                    }
                }
                field("URL", hint: parsed == nil ? nil : "Only changes if you edit it.", error: parsed == nil ? "That isn\u{2019}t a valid link." : nil, focused: field == .url) {
                    TextField("", text: $url, prompt: Text("https://…").foregroundStyle(LW.muted))
                        .focused($field, equals: .url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(commit)
                }
            }

            // Dialog footer: pills, concentric with the card's bottom corners; one primary.
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.buttonStyle(LWButton(variant: .secondary, radius: LWFloatingSheet<EmptyView>.innerRadius, height: 48, fill: true))
                Button("Save") { commit() }.buttonStyle(LWButton(variant: .primary, radius: LWFloatingSheet<EmptyView>.innerRadius, height: 48, fill: true)).disabled(parsed == nil)
            }
            .padding(.top, 4)
        }
        // One margin on every side (the floating sheet's), with the title a little lower.
        .padding(.horizontal, LWFloatingSheet<EmptyView>.pad)
        .padding(.top, 22)
        .padding(.bottom, LWFloatingSheet<EmptyView>.pad)
        .tint(LW.ink)
        .environment(\.colorScheme, .dark)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { field = .name } }
    }

    private func field<Content: View>(_ label: String, hint: String?, error: String? = nil, focused: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(LW.label).foregroundStyle(LW.ink)
            HStack(spacing: 6) { content() }
                .font(LW.body)
                .foregroundStyle(LW.ink)
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .lwField(focused: focused, invalid: error != nil, height: 44)
            if let text = error ?? hint {
                Text(text).font(LW.caption).foregroundStyle(error != nil ? LW.danger : LW.muted)
                    .transition(.opacity)
            }
        }
        .animation(LW.easeOut, value: error)
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

/// Nothing saved yet: the kit's empty state — a wash-1 well with an icon tile, a title and one line.
private struct LinkDirectoryEmpty: View {
    var body: some View {
        VStack(spacing: 0) {
            LWIconTile(symbol: "link", size: 44)
                .padding(.bottom, 12)
            Text("No saved links yet")
                .font(LW.sans(15, .semibold))
                .foregroundStyle(LW.ink)
                .padding(.bottom, 4)
            Text("Paste a Vercel link above. Prototypes you open are saved here.")
                .font(LW.sans(13))
                .foregroundStyle(LW.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous).fill(LW.wash(1)))
        .overlay(RoundedRectangle(cornerRadius: LW.R.tile, style: .continuous).strokeBorder(LW.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - row swipe gesture

/// Horizontal swipe for a row. iOS 18+: a UIKit pan that only begins when the movement is
/// clearly sideways, so vertical drags always go to the list's scroll view. iOS 17: the
/// previous simultaneous DragGesture.
private struct RowSwipe: ViewModifier {
    let changed: (CGFloat) -> Void
    let ended: (_ translation: CGFloat, _ flung: CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(HorizontalPan(changed: changed, ended: ended))
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                        changed(v.translation.width)
                    }
                    .onEnded { v in ended(v.translation.width, v.predictedEndTranslation.width) }
            )
        }
    }
}

@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.maximumNumberOfTouches = 1
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let t = g.translation(in: g.view).x
        switch g.state {
        case .began, .changed: changed(t)
        case .ended:
            // Momentum like SwiftUI's predictedEndTranslation: where a fling at this speed would land.
            ended(t, t + g.velocity(in: g.view).x * 0.18)
        case .cancelled, .failed:
            // Interrupted (a call, backgrounding, the list scrolling): never delete or edit on
            // that, just settle back to where the row was.
            ended(.nan, .nan)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only start for clearly sideways movement; anything else is the list's scroll.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view), t = pan.translation(in: pan.view)
            let dx = abs(v.x) > 1 || abs(v.y) > 1 ? abs(v.x) : abs(t.x)
            let dy = abs(v.x) > 1 || abs(v.y) > 1 ? abs(v.y) : abs(t.y)
            return dx > dy * 1.3
        }
    }
}
