import SwiftUI
import WebKit
import UIKit
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    var interfaceStyle: UIUserInterfaceStyle { self == .light ? .light : self == .dark ? .dark : .unspecified }
}

/// The prototype's own "design variations" picker (1 · 2 · 3 · 4 · reset), found in the page.
struct Switcher: Equatable {
    enum Kind: String { case option, reset, action }
    struct Item: Equatable, Identifiable {
        let index: Int        // control index inside the page's picker
        let kind: Kind
        let text: String      // "2", "Reset the flow", "Spec Sheet"
        var selected: Bool
        var id: Int { index }
        var isReset: Bool { kind == .reset }
        var isOption: Bool { kind == .option }
        /// SF Symbol for non-numbered controls.
        var symbol: String {
            if kind == .reset { return "arrow.counterclockwise" }
            let t = text.lowercased()
            if t.contains("spec") || t.contains("sheet") || t.contains("setting") || t.contains("option") || t.contains("filter") { return "slider.horizontal.3" }
            if t.contains("info") || t.contains("about") { return "info.circle" }
            if t.contains("share") { return "square.and.arrow.up" }
            return "ellipsis"
        }
    }
    var label: String
    var items: [Item]
    var options: [Item] { items.filter(\.isOption) }
}

@MainActor
final class AppModel: NSObject, ObservableObject {
    // MARK: state
    @Published var currentURL: URL?
    @Published var lockVisible = true {
        didSet {
            // A page loading out of sight behind the lock screen must not buzz the phone.
            HapticEngine.shared.suppressed = lockVisible
            if oldValue != lockVisible { debugLog("lockVisible → \(lockVisible)") }
        }
    }
    /// The prototype's saved first screen, shown until the live page is ready (LaunchCache).
    @Published private(set) var launchImage: UIImage?
    @Published private(set) var launchFading = false
    private var snapshotPending = false
    @Published var panelOpen = false
    /// The prototype menu's own height, so its floating sheet fits it exactly (no scrolling).
    @Published var menuHeight: CGFloat = 0
    /// The how-to guide, opened only from the lock screen's Quick tour button.
    @Published var guideOpen = false
    /// The lock screen's link field has submitted and is waiting for the keyboard to go.
    @Published var linkSubmitting = false
    /// The lock screen's "Join a room" sheet (Pushed from web ▸ Set up).
    @Published var pushJoinOpen = false
    /// The full Link Directory page over the lock screen.
    @Published var directoryOpen = false
    /// The full Pushed from web page over the lock screen.
    @Published var pushPageOpen = false
    /// The saved link being edited (Link Directory ▸ Edit); the lock screen blurs behind its sheet.
    @Published var editingLink: SavedLink?
    @Published var switcher: Switcher?
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var loadError: String?
    /// The prototype has painted its first complete screen (fonts + on-screen images ready).
    @Published private(set) var contentShown = false
    /// Waiting on the lock screen for the page to be ready before revealing it.
    @Published private(set) var opening = false
    /// A load from the lock-screen widget that failed: shown in the widget.
    @Published var openFailure: String?
    private var readyTimeout: DispatchWorkItem?
    /// Short fallback after a finished load whose page never sent its ready signal (a page
    /// restored from the back-forward cache, or one whose scripts failed), so a cross-fade
    /// can never hold a frozen screen.
    private var readyFallback: DispatchWorkItem?
    /// Back/forward history items that belong to the prototype open now. The swipe-back
    /// gesture is only enabled while the previous item is one of them, so it can never land
    /// on about:blank or on an earlier prototype.
    private var sessionItems = Set<ObjectIdentifier>()
    private var urlObservation: NSKeyValueObservation?
    /// The last real page shown in this prototype (it may have navigated since it opened).
    /// Used to restore it after the page's process dies and when going Home.
    private var lastPageURL: URL?
    /// The kind of the main-frame navigation WebKit is about to start.
    private var pendingNavigationType: WKNavigationType = .other
    /// Bumped on every fresh load, so a deferred load from an older open can't run late.
    private var loadGeneration = 0
    /// When the page's web process last died (memory), to stop a reload loop.
    private var crashes: [Date] = []
    /// The link the current open added to recents (nil if it was already there).
    private var newRecent: String?
    /// A link waiting to go into the Link Directory: saved only once its page has really
    /// loaded, so typos, dead servers and error pages never become entries.
    private var pendingSave: URL?
    /// HTTP status of the last main-frame response (0 = not HTTP / not seen yet).
    private var lastHTTPStatus = 0
    /// The detected phone and how the 375 × 812 base is fitted to it.
    @Published private(set) var device = DeviceProfile.current(fitBase: true)

    // MARK: settings (persisted)
    @Published var recents: [String] { didSet { defaults.set(recents, forKey: "recents") } }
    /// Every link submitted from the link field or the options sheet, saved automatically.
    let directory = LinkDirectory()
    /// Rooms on the web push page (Vercel Sim Push) this iPhone listens to.
    let push = PushHub(model: DeviceProfile.modelName)
    @Published var showStatusBar: Bool { didSet { defaults.set(showStatusBar, forKey: "showStatusBar") } }
    @Published var showHomeIndicator: Bool { didSet { defaults.set(showHomeIndicator, forKey: "showHomeIndicator") } }
    @Published var showIterationPill: Bool { didSet { defaults.set(showIterationPill, forKey: "showIterationPill") } }
    @Published var hapticsOn: Bool { didSet { defaults.set(hapticsOn, forKey: "hapticsOn"); HapticEngine.shared.enabled = hapticsOn } }
    @Published var fitBase: Bool { didSet { defaults.set(fitBase, forKey: "fitBase"); applyZoom() } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); webView.overrideUserInterfaceStyle = appearance.interfaceStyle } }

    let webView: WKWebView
    private let defaults = UserDefaults.standard
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    static let baseWidth: CGFloat = 375 // design base: iPhone 13 mini, 375 × 812

    override init() {
        let d = UserDefaults.standard
        recents = d.stringArray(forKey: "recents") ?? []
        showStatusBar = d.object(forKey: "showStatusBar") as? Bool ?? false
        showHomeIndicator = d.object(forKey: "showHomeIndicator") as? Bool ?? false
        showIterationPill = d.object(forKey: "showIterationPill") as? Bool ?? false
        fitBase = d.object(forKey: "fitBase") as? Bool ?? true
        hapticsOn = d.object(forKey: "hapticsOn") as? Bool ?? true
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default() // keeps Vercel sign-ins between launches
        config.ignoresViewportScaleLimits = false // honour the locked min/max scale below
        let hapticBridge = HapticMessageHandler()
        (HapticMessageHandler.publicNames + HapticMessageHandler.internalNames).forEach {
            config.userContentController.add(hapticBridge, name: $0)
        }
        let readyBridge = ReadyMessageHandler()
        config.userContentController.add(readyBridge, name: "__vsReady")
        webView = FullBleedWebView(frame: .zero, configuration: config)
        super.init()
        readyBridge.model = self
        push.app = self

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // Full-bleed like a home-screen web app: the page gets env(safe-area-inset-*)
        // and lays out under the notch itself.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false // long-press on a link: no Safari-style preview
        // Fixed to the screen: no pinch, no zoom bounce (double-tap zoom is off via CSS).
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.bouncesZoom = false
        webView.overrideUserInterfaceStyle = appearance.interfaceStyle
        if #available(iOS 16.4, *) { webView.isInspectable = true } // Safari ▸ Develop
        applyZoom()

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in self?.progress = wv.estimatedProgress }
        }
        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in self?.isLoading = wv.isLoading }
        }
        // The page's title names its directory entry, whenever it arrives or changes (SPAs set it late).
        // Every URL change (loads and the page's own pushState) adds the current history item
        // to this prototype's session and updates whether swipe-back is allowed.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.trackHistory() }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor in
                // Only while the page is still the opened link: after the prototype navigates
                // (another iteration, /v5), its title belongs to that page, not this entry.
                guard let self, let url = self.currentURL, let title = wv.title, self.pageIsOpenedLink(url) else { return }
                self.directory.setTitle(title, for: url)
            }
        }
        HapticEngine.shared.enabled = hapticsOn
        HapticEngine.shared.prepare()
        handleLaunchArguments()
    }

    // MARK: 375 base layout
    /// Designs are made at 375 pt wide. On wider iPhones the page is zoomed so it still lays
    /// out at 375 CSS px and fills the screen with the same proportions.
    func applyZoom() {
        device = DeviceProfile.current(fitBase: fitBase)
        // The 375 base comes from the viewport tag (layout width 375, scale = width/375),
        // not pageZoom: pageZoom leaves 100vw at the full screen width, so pages overflowed
        // and WebKit let them zoom out.
        webView.pageZoom = 1
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: Scripts.hideSwitcherStyle, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Scripts.haptics, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: Scripts.readySignal, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let lock = Scripts.viewportLock(width: fitBase ? "\(Int(DeviceProfile.base.width))" : "device-width", scale: device.zoom)
        ucc.addUserScript(WKUserScript(source: lock, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if currentURL != nil { webView.evaluateJavaScript(lock, completionHandler: nil) }
        (webView as? FullBleedWebView)?.insetScale = device.zoom
        (webView as? FullBleedWebView)?.refreshInsets()
        debugLog("device: \(device.name) \(Int(device.screen.width))×\(Int(device.screen.height)) @\(Int(device.scale))x, safe \(Int(device.safeArea.top))/\(Int(device.safeArea.bottom)) → \(device.fitSummary)")
    }

    /// Re-detect once the window exists (safe areas aren't known at launch).
    func refreshDevice() { applyZoom() }

    // MARK: navigation
    /// Reveal choreography:
    /// · from the lock screen: load behind it (the widget shows a spinner), and reveal only
    ///   once the page reports ready, so the first frame you see is the finished screen;
    /// · while a prototype is showing: hold the current screen and cross-fade to the new one;
    /// · the same prototype that's already running: reveal immediately.
    @discardableResult
    func open(_ raw: String, revealNow: Bool = false, save: Bool = true) -> Bool {
        debugLog("open(\(raw))")
        // An invite to a web push room (its link pasted in a field, or shared in): join it.
        if let invite = PushHub.invite(from: raw) {
            panelOpen = false
            push.join(invite)
            return true
        }
        guard let url = Self.normalize(raw) else { debugLog("  invalid URL"); return false }
        // A second tap on the link that's already opening: let the first one finish.
        if opening, currentURL?.absoluteString == url.absoluteString {
            debugLog("  already opening; ignored")
            return true
        }
        guideOpen = false
        editingLink = nil
        pushJoinOpen = false          // no sheet left up behind the prototype
        loadError = nil
        openFailure = nil
        newRecent = recents.contains(where: { Self.sameDocument(URL(string: $0), url) }) ? nil : url.absoluteString
        addRecent(url.absoluteString)
        pendingSave = save ? url : nil
        defaults.set(url.absoluteString, forKey: "lastURL")
        panelOpen = false
        // Reuse the running page only for the very same URL: a link that differs in its query
        // or #fragment (?v=2, #screen-3) is a different preview and loads as sent.
        if let current = currentURL, current.absoluteString == url.absoluteString, webView.url != nil, contentShown {
            // Back from the lock screen: the prototype is still running (and already loaded).
            commitPendingSave()
            reveal()
            return true
        }
        switcher = nil
        pressedOption = nil
        currentURL = url
        launchImage = nil
        startSession()
        let saved = LaunchCache.image(for: url, size: webView.bounds.size)
        snapshotPending = saved == nil || lockVisible // refresh the snapshot on every fresh open
        if lockVisible, let saved {
            // Seen before: reveal at once on its saved first screen, cross-fade to live.
            contentShown = false
            launchImage = saved
            armReadyTimeout()
            loadWhenOnScreen(url)
            reveal()
            debugLog("  opening \(url.absoluteString) on its launch snapshot")
            return true
        }
        if lockVisible && !revealNow {
            contentShown = false
            opening = true
        } else if contentShown {
            (webView as? FullBleedWebView)?.freeze() // cross-fade from what's on screen
        } else {
            contentShown = false
        }
        armReadyTimeout()
        loadWhenOnScreen(url)
        if revealNow { reveal() }
        debugLog("  opening \(url.absoluteString) (from lock: \(lockVisible), reveal now: \(revealNow))")
        return true
    }

    // MARK: history (swipe back / forward)

    /// Back / forward within this prototype only (the same rule as the edge swipe).
    /// The page on screen is still the link that was opened: the same document, or the first
    /// (and only) page of this session, which covers links that redirect as they load.
    func pageIsOpenedLink(_ url: URL) -> Bool {
        Self.sameDocument(webView.url, url) || sessionItems.count <= 1
    }

    var canGoBack: Bool { currentURL != nil && webView.canGoBack && webView.backForwardList.backItem.map { sessionItems.contains(ObjectIdentifier($0)) } == true }
    var canGoForward: Bool { currentURL != nil && webView.canGoForward }
    func goBack() { if canGoBack { webView.goBack() } }
    func goForward() { if canGoForward { webView.goForward() } }

    /// A fresh prototype starts its own history; earlier items stay unreachable by swipe.
    private func startSession() {
        sessionItems.removeAll()
        lastPageURL = nil
        webView.allowsBackForwardNavigationGestures = false
    }

    private func trackHistory() {
        let list = webView.backForwardList
        // Only once the item is the page on screen: while a new load is starting, `url` is
        // already the new address but `currentItem` is still the previous page.
        if currentURL != nil, let item = list.currentItem, item.url == webView.url,
           ["http", "https"].contains(item.url.scheme?.lowercased() ?? "") {
            sessionItems.insert(ObjectIdentifier(item))
            lastPageURL = item.url
        }
        let canSwipe = currentURL != nil && list.backItem.map { sessionItems.contains(ObjectIdentifier($0)) } == true
        if webView.allowsBackForwardNavigationGestures != canSwipe {
            webView.allowsBackForwardNavigationGestures = canSwipe
            debugLog("swipe-back \(canSwipe ? "on" : "off") (\(sessionItems.count) in session)")
        }
    }

    /// The lock screen slides away and the prototype grows into place (see RootView).
    private func reveal() {
        opening = false
        guard lockVisible else { return }
        revealAck = false
        withAnimation(Self.revealSpring) { lockVisible = false }
        unmountWork?.cancel()
        let unmount = DispatchWorkItem { [weak self] in
            guard let self, !self.lockVisible else { return }
            self.lockMounted = false
        }
        unmountWork = unmount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: unmount)
        HapticEngine.shared.play(message: "soft") // after: lock-screen haptics are suppressed
        // Watchdog: the root view acknowledges the reveal when it renders it. If that hasn't
        // happened shortly after, nudge SwiftUI with a fresh publish so it can't stay stuck.
        ensureRevealRendered(attempt: 0)
    }

    /// SwiftUI occasionally drops the reveal's update when it lands in the same turn as
    /// WebKit's first layer commit. Re-publish inside the same animation a few frames later,
    /// so it still animates instead of jumping.
    private func ensureRevealRendered(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, !self.lockVisible, !self.revealAck, attempt < 6 else { return }
            debugLog("reveal not rendered yet; nudging (\(attempt + 1))")
            withAnimation(Self.revealSpring) { self.renderNudge &+= 1 }
            self.ensureRevealRendered(attempt: attempt + 1)
        }
    }
    /// The lock screen is in the view hierarchy (false once a reveal has finished).
    @Published private(set) var lockMounted = true
    private var unmountWork: DispatchWorkItem?
    /// Set by RootView once it has rendered the revealed state.
    var revealAck = true
    @Published private(set) var renderNudge = 0
    static let revealSpring = Animation.spring(response: 0.52, dampingFraction: 1.0)

    /// Called by the page's ready signal (Scripts.readySignal), or by the timeout.
    /// A ready signal sent by a page: ignored when it comes from the page being replaced (a
    /// late message from the old page must not reveal the new one half-built).
    func pageSignalledReady(_ why: String, href: String) {
        if let from = URL(string: href), let now = webView.url, !Self.sameDocument(from, now) {
            debugLog("ready signal from \(href) ignored (now loading \(now.absoluteString))")
            return
        }
        pageBecameReady(why)
    }

    func pageBecameReady(_ why: String) {
        readyTimeout?.cancel()
        readyFallback?.cancel()
        let sv = webView.scrollView
        let locked = abs(sv.zoomScale - device.zoom) < 0.005
        debugLog("page ready (\(why)); viewport locked: \(locked)")
        commitPendingSave()
        if let url = currentURL, let title = webView.title, pageIsOpenedLink(url) { directory.setTitle(title, for: url) }
        if !locked { verifyViewportLock() }
        // One more frame so WebKit has composited what the page just painted.
        DispatchQueue.main.asyncAfter(deadline: .now() + (locked ? 0.03 : 0.25)) { [weak self] in
            guard let self, self.currentURL != nil else { return }
            if self.launchImage != nil {
                // Live page goes fully opaque *under* the snapshot, then only the snapshot fades
                // off the top: never two half-transparent layers showing the backdrop between them.
                self.contentShown = true
                withAnimation(.easeOut(duration: 0.32)) { self.launchFading = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    self.launchImage = nil
                    self.launchFading = false
                }
            } else {
                withAnimation(.easeOut(duration: 0.28)) { self.contentShown = true }
            }
            (self.webView as? FullBleedWebView)?.unfreeze()
            debugLog("ready → reveal? opening \(self.opening), lock \(self.lockVisible)")
            if self.opening { self.reveal() }
            // Pickers rendered by the page's own script appear after the load event: look
            // again now, and once more a little later if there's still none.
            self.scanSwitcher()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if let self, self.switcher == nil { self.scanSwitcher() }
            }
            // Snapshot only after the reveal has finished: taking one mid-animation forces a
            // Core Animation flush that can swallow the SwiftUI update for the reveal.
            if self.snapshotPending, why != "timeout", let url = self.currentURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self, self.currentURL == url, !self.lockVisible else { return }
                    self.saveLaunchSnapshot(for: url)
                }
            }
        }
    }

    private func saveLaunchSnapshot(for url: URL) {
        snapshotPending = false
        let size = webView.bounds.size
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { image, _ in
            if let image { LaunchCache.store(image, for: url, size: size) }
        }
    }

    /// After `didFinish`: if no ready signal follows shortly, finish the reveal / cross-fade.
    fileprivate func armReadyFallback() {
        readyFallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.currentURL != nil else { return }
            self.pageBecameReady("finished without a ready signal")
        }
        readyFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// A navigation that stopped without a new page (cancelled, a download, a swipe that
    /// went nowhere): drop the cross-fade so the live page shows again.
    fileprivate func navigationEnded() {
        guard !webView.isLoading else { return }
        readyTimeout?.cancel()
        (webView as? FullBleedWebView)?.unfreeze()
        if currentURL != nil, !contentShown, !opening { withAnimation(.easeOut(duration: 0.2)) { contentShown = true } }
    }

    private func armReadyTimeout() {
        readyTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pageBecameReady("timeout") }
        readyTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// A load that failed before anything was shown: report it where the user is.
    /// The opened page loaded: save it, unless the server answered with an error page.
    fileprivate func commitPendingSave() {
        guard let url = pendingSave, let current = currentURL, Self.sameDocument(url, current) else { return }
        pendingSave = nil
        if lastHTTPStatus >= 400 { debugLog("not saving \(url.absoluteString): HTTP \(lastHTTPStatus)"); return }
        directory.save(url)
        if let title = webView.title, pageIsOpenedLink(url) { directory.setTitle(title, for: url) }
    }

    fileprivate func loadFailed(_ message: String) {
        debugLog("loadFailed: \(message) (opening \(opening))")
        pendingSave = nil
        readyTimeout?.cancel()
        readyFallback?.cancel()
        (webView as? FullBleedWebView)?.unfreeze()
        if opening {
            // A link that never opened isn't what swipe-up should bring back.
            if let failed = currentURL?.absoluteString, failed == newRecent, recents.first == failed {
                recents.removeFirst()
                if let previous = recents.first { defaults.set(previous, forKey: "lastURL") } else { defaults.removeObject(forKey: "lastURL") }
            }
            opening = false
            openFailure = message
            currentURL = nil
            contentShown = false
        } else {
            loadError = message
        }
    }

    /// WebKit sizes the viewport and safe areas from the view's frame when a load starts. A
    /// load begun before the web view is on screen (e.g. at cold launch) lays out at the
    /// 980-px desktop default with zero insets, so wait for a window and a real size.
    private func loadWhenOnScreen(_ url: URL) {
        readyFallback?.cancel()          // the previous page's fallback must not reveal this one
        loadGeneration &+= 1
        let generation = loadGeneration
        guard let wv = webView as? FullBleedWebView, wv.window == nil || wv.bounds.width < 1 else {
            (webView as? FullBleedWebView)?.refreshInsets()
            debugLog("  loading (on screen, width \(webView.bounds.width))")
            webView.load(URLRequest(url: url))
            return
        }
        debugLog("  deferring load until on screen (window \(wv.window != nil), width \(wv.bounds.width))")
        var done = false
        let go: () -> Void = { [weak self, weak wv] in
            guard !done else { return }
            done = true
            // A newer open (or Home) has taken over since this load was deferred.
            guard let self, self.loadGeneration == generation, self.currentURL != nil else { return }
            wv?.onReady = nil
            wv?.refreshInsets()
            debugLog("  loading now (window \(wv?.window != nil), width \(wv?.bounds.width ?? 0))")
            self.webView.load(URLRequest(url: url))
        }
        wv.onReady = go
        // Safety net: never leave a pasted link waiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: go)
    }

    /// After load: if WebKit's zoom doesn't match the lock (it can lag behind on a slow
    /// first launch), re-apply the viewport so the page snaps to the device scale.
    private func verifyViewportLock(attempt: Int = 0) {
        let sv = webView.scrollView
        let ok = abs(sv.zoomScale - device.zoom) < 0.005 && abs(sv.maximumZoomScale - sv.minimumZoomScale) < 0.005
        guard !ok, attempt < 4 else { return }
        debugLog("viewport lock drifted (zoom \(sv.zoomScale) [\(sv.minimumZoomScale)–\(sv.maximumZoomScale)]); re-applying")
        (webView as? FullBleedWebView)?.refreshInsets()
        let lock = Scripts.viewportLock(width: fitBase ? "\(Int(DeviceProfile.base.width))" : "device-width", scale: device.zoom)
        // Nudge: blank the tag, then set it, so WebKit recomputes the viewport.
        webView.evaluateJavaScript("document.querySelectorAll('meta[name=\"viewport\" i]').forEach((m) => m.setAttribute('content', 'width=device-width')); \(lock)", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.verifyViewportLock(attempt: attempt + 1) }
    }

    /// Swipe up on the lock screen: resume the running prototype, else the most recent one,
    /// else ask for a URL.
    func unlock() {
        debugLog("unlock (current=\(currentURL?.absoluteString ?? "nil"), recents=\(recents.count))")
        if let current = currentURL, contentShown {
            open(current.absoluteString, save: false)
        } else if let target = currentURL?.absoluteString ?? recents.first {
            // The finger already moved the lock away: reveal now and fade the page in when ready.
            open(target, revealNow: true, save: false)
        } else {
            panelOpen = true
        }
    }

    /// Close the prototype and go back to the lock screen.
    func goHome() {
        debugLog("goHome")
        // Remember the page actually on screen (the prototype may have navigated, e.g. to
        // another iteration), so swipe-up reopens that and not the link first opened.
        if currentURL != nil, let page = lastPageURL ?? webView.url, ["http", "https"].contains(page.scheme?.lowercased() ?? "") {
            addRecent(page.absoluteString)
        }
        panelOpen = false
        switcher = nil
        pressedOption = nil
        loadError = nil
        currentURL = nil
        opening = false
        readyTimeout?.cancel()
        readyFallback?.cancel()
        loadGeneration &+= 1
        unmountWork?.cancel()
        startSession()
        (webView as? FullBleedWebView)?.unfreeze(animated: false)
        if !lockMounted {
            // Put it back above the screen first, then let it slide down into place.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { lockMounted = true }
            DispatchQueue.main.async { withAnimation(Self.revealSpring) { self.lockVisible = true } }
        } else {
            withAnimation(Self.revealSpring) { lockVisible = true }
        }
        // Unload once the lock screen covers it, so nothing visibly blanks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.currentURL == nil else { return }
            self.contentShown = false
            self.launchImage = nil
            self.webView.stopLoading()
            self.webView.load(URLRequest(url: URL(string: "about:blank")!))
        }
    }

    /// Back in the foreground. iOS may have killed the page's process while the app was
    /// away (the screen would stay blank until a touch); ping it and reload straight away if
    /// it's gone. Also lands any cross-fade that was waiting while the app was suspended.
    func appBecameActive() {
        guard let url = currentURL else { return }
        webView.evaluateJavaScript("1") { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.currentURL == url else { return }
                if let error = error as? WKError, error.code == .webContentProcessTerminated {
                    debugLog("foreground: page process was gone; reloading")
                    self.reload()
                } else if !self.webView.isLoading {
                    self.navigationEnded()
                }
            }
        }
    }

    func reload() {
        // "Try again" after a failed link retries that link. The web view may still hold the
        // previous page (a failed load never commits), and reloading it would load the wrong one.
        let retry = loadError != nil
        loadError = nil
        if contentShown { (webView as? FullBleedWebView)?.freeze() }
        armReadyTimeout()
        if retry, let url = currentURL {
            debugLog("retrying \(url.absoluteString)")
            loadWhenOnScreen(url)
            return
        }
        // After the page's process died WebKit forgets the page: load the one that was on screen.
        if webView.url == nil || webView.url?.absoluteString == "about:blank", let url = lastPageURL ?? currentURL {
            loadWhenOnScreen(url)
        } else {
            webView.reload()
        }
    }

    func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    func removeRecents(at offsets: IndexSet) { recents.remove(atOffsets: offsets) }

    /// Snapshot of the prototype at device resolution, handed to the share sheet
    /// (Save Image, AirDrop, Messages…). The options sheet closes first so it isn't in it.
    func takeScreenshot() {
        panelOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            let config = WKSnapshotConfiguration()
            config.afterScreenUpdates = true
            self.webView.takeSnapshot(with: config) { image, _ in
                guard let image, let top = Self.topViewController() else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = top.view
                top.present(share, animated: true)
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    private func addRecent(_ url: String) {
        recents = [url] + recents.filter { !Self.sameDocument(URL(string: $0), URL(string: url)) }
        if recents.count > 12 { recents = Array(recents.prefix(12)) }
    }

    /// The options sheet, from the two-finger double-tap or a shake: never over another sheet,
    /// and the keyboard goes first so typing can't land in a field hidden behind it.
    func openOptions() {
        guard editingLink == nil, !guideOpen, !pushJoinOpen, !panelOpen else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        panelOpen = true
    }

    // MARK: iteration switcher
    func scanSwitcher() {
        guard currentURL != nil else { return }
        let generation = loadGeneration
        webView.evaluateJavaScript(Scripts.scanSwitcher) { [weak self] result, _ in
            Task { @MainActor in
                // A result from a page that has since been replaced belongs to that page.
                guard let self, self.loadGeneration == generation, self.currentURL != nil else { return }
                #if DEBUG
                if self.fakeIterations > 0 { self.switcher = self.fakeSwitcher(); return }
                #endif
                var parsed = Self.parseSwitcher(result)
                // A just-pressed iteration stays highlighted until the page agrees (or 3 s pass):
                // a scan taken while the new iteration is still loading reads its default "1".
                if let p = self.pressedOption, var sw = parsed {
                    let agrees = sw.items.first(where: \.selected)?.index == p.index
                    if agrees || Date() > p.until { self.pressedOption = nil }
                    else if sw.items.contains(where: { $0.index == p.index }) {
                        for i in sw.items.indices { sw.items[i].selected = sw.items[i].index == p.index }
                        parsed = sw
                    }
                }
                self.switcher = parsed
            }
        }
    }

    /// The iteration last pressed and how long to trust it over what the page reports.
    private var pressedOption: (index: Int, until: Date)?

    func press(_ item: Switcher.Item) {
        #if DEBUG
        if fakeIterations > 0 { fakeSelected = item.isOption ? item.index : 0; switcher = fakeSwitcher(); return }
        #endif
        if item.isOption, var s = switcher {
            // Optimistic highlight; the rescan confirms it.
            for i in s.items.indices { s.items[i].selected = s.items[i].index == item.index }
            switcher = s
            pressedOption = (item.index, Date().addingTimeInterval(3))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        webView.evaluateJavaScript(Scripts.press(index: item.index), completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.scanSwitcher() }
    }

    func stepIteration(_ delta: Int) {
        guard let opts = switcher?.options, !opts.isEmpty else { return }
        let cur = opts.firstIndex(where: \.selected) ?? 0
        press(opts[(cur + delta + opts.count) % opts.count])
    }

    private static func parseSwitcher(_ result: Any?) -> Switcher? {
        guard let dict = result as? [String: Any], let raw = dict["items"] as? [[String: Any]] else { return nil }
        let items = raw.compactMap { item -> Switcher.Item? in
            guard let index = item["i"] as? Int, let kind = item["kind"] as? String else { return nil }
            return Switcher.Item(index: index, kind: Switcher.Kind(rawValue: kind) ?? .action, text: item["text"] as? String ?? "",
                                 selected: item["selected"] as? Bool ?? false)
        }
        guard items.contains(where: \.isOption) else { return nil }
        // Only the iterations and reset: named controls such as "Spec Sheet" aren't offered
        // in the phone app.
        return Switcher(label: dict["label"] as? String ?? "", items: items.filter { $0.kind != .action })
    }

    // MARK: URL helpers
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if s.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) == nil {
            let local = s.range(of: #"^(localhost|127\.|\[::1\]|[\w-]+\.local)(:|/|$)"#, options: .regularExpression) != nil
            s = (local ? "http://" : "https://") + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    static func display(_ raw: String) -> String {
        guard let u = URL(string: raw), let host = u.host else { return raw }
        let path = u.path == "/" ? "" : u.path
        return host + (u.port.map { ":\($0)" } ?? "") + path
    }

    static func sameDocument(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        return a.host == b.host && a.port == b.port && a.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == b.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: links from other apps

    /// A link handed to the app by iOS — `vercelsim://open?url=<encoded>` (the share sheet's
    /// "Vercel Sim" and any shortcut), `vercelsim://my-app.vercel.app/path?q#f`, or a plain
    /// https link. The prototype URL is used exactly as sent: path, query and #fragment kept.
    func openIncoming(_ link: URL) {
        debugLog("incoming link: \(link.absoluteString)")
        if let invite = PushHub.invite(from: link.absoluteString) {   // vercelsim://pair?room=… (the web page's QR code)
            editingLink = nil
            pushJoinOpen = false
            panelOpen = false
            push.join(invite)
            return
        }
        guard let target = Self.prototypeURL(from: link) else { debugLog("  no prototype URL in it"); return }
        editingLink = nil
        open(target)
    }

    static func prototypeURL(from link: URL) -> String? {
        guard link.scheme?.lowercased() == "vercelsim" else { return link.absoluteString }
        if let q = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value, !q.isEmpty {
            return q
        }
        var rest = String(link.absoluteString.dropFirst("vercelsim://".count))
        if rest.hasPrefix("open/") { rest.removeFirst(5) }
        if rest.isEmpty || rest == "open" { return nil }
        return rest.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil ? rest : "https://" + rest
    }

    // MARK: launch arguments (review / automation)
    // -url <url>        open a prototype straight away
    // -panel            show the control panel
    // -iteration <n>    press iteration n once the page has loaded
    // -pill             show the on-screen iteration pill
    private var pendingIteration: Int?
    #if DEBUG
    private var fakeIterations = 0
    private var fakeSelected = 4
    private func fakeSwitcher() -> Switcher {
        var items = (0..<fakeIterations).map { Switcher.Item(index: $0, kind: .option, text: "\($0 + 1)", selected: $0 == fakeSelected) }
        items.append(Switcher.Item(index: fakeIterations, kind: .reset, text: "Reset", selected: false))
        return Switcher(label: "Iterations", items: items)
    }
    #endif
    @Published private(set) var pillThisLaunch = false
    var pillVisible: Bool { showIterationPill || pillThisLaunch }
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        // Testing flag: show the pill for this launch only, without saving the setting.
        if args.contains("-pill") { pillThisLaunch = true }
        #if DEBUG
        // Testing: -fakeIterations 12 shows a 12-iteration picker for any page.
        if let n = value("-fakeIterations").flatMap(Int.init) { fakeIterations = n }
        #endif
        if let n = value("-iteration").flatMap(Int.init) { pendingIteration = n }
        if let url = value("-url") { DispatchQueue.main.async { self.open(url) } }
        if args.contains("-joinSheet") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.pushJoinOpen = true } }
        if args.contains("-pushPage") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.pushPageOpen = true } }
        if args.contains("-directory") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.directoryOpen = true } }
        if args.contains("-panel") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.panelOpen = true } }
    }

    fileprivate func pageDidLoad() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.verifyViewportLock() }
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [webView] in webView.evaluateJavaScript("(() => { const t = document.createElement('div'); t.style.cssText = 'position:fixed;padding:env(safe-area-inset-top) 0 env(safe-area-inset-bottom)'; document.documentElement.appendChild(t); const cs = getComputedStyle(t); const r = [location.pathname, innerWidth + '×' + innerHeight, 'dpr ' + devicePixelRatio.toFixed(2), 'safe ' + cs.paddingTop + '/' + cs.paddingBottom, (document.querySelector('meta[name=viewport]') || {}).content, 'scrollW ' + document.documentElement.scrollWidth, 'scrollH ' + document.documentElement.scrollHeight, 'frame ' + (() => { const f = [...document.body.querySelectorAll('*')].find((e) => { const r = e.getBoundingClientRect(); return r.width >= 370 && r.height >= 600; }); if (!f) return '-'; const r = f.getBoundingClientRect(); return (f.className || f.tagName).toString().split(' ')[0] + ' ' + r.left.toFixed(0) + ',' + r.top.toFixed(0) + ' ' + r.width.toFixed(0) + '×' + r.height.toFixed(1); })(), 'vv ' + (visualViewport ? visualViewport.width.toFixed(0) + '×' + visualViewport.height.toFixed(0) + '@' + visualViewport.scale.toFixed(2) : '-')].join(' | '); t.remove(); return r; })()") { r, _ in
            let sv = webView.scrollView
            debugLog("page loaded: \(r ?? "?") (pageZoom \(webView.pageZoom), zoom \(sv.zoomScale) [\(sv.minimumZoomScale)–\(sv.maximumZoomScale)], content \(Int(sv.contentSize.width))×\(Int(sv.contentSize.height)))")
        } }
        #endif
        scanSwitcher()
        if let n = pendingIteration {
            pendingIteration = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let item = self.switcher?.options.first(where: { $0.text == String(n) }) else { return }
                self.press(item)
            }
        }
    }
}

func debugLog(_ s: String) {
    #if DEBUG
    print("[VercelSim] \(s)")
    #endif
}

/// A web view laid out full-screen that still reports the device's real safe area to the
/// page. SwiftUI's .ignoresSafeArea() zeroes the hosted view's insets, which would make
/// every env(safe-area-inset-*) 0 — so take them from the window instead.
final class FullBleedWebView: WKWebView {
    /// Page scale applied by the viewport lock. WebKit reports env(safe-area-inset-*) in
    /// screen points, so divide by the scale to get the page's CSS px
    /// (62/34 pt on a 17 Pro Max → 53/29 in the 375 layout).
    var insetScale: CGFloat = 1
    override var safeAreaInsets: UIEdgeInsets {
        guard let w = window else { return super.safeAreaInsets }
        let k = max(insetScale, 1), i = w.safeAreaInsets
        return UIEdgeInsets(top: i.top / k, left: i.left / k, bottom: i.bottom / k, right: i.right / k)
    }
    /// Push the current insets to WebKit (call before loading and after zoom changes).
    func refreshInsets() {
        lastReported = safeAreaInsets
        safeAreaInsetsDidChange()
    }
    /// Cross-fades: hold a snapshot of the current screen over the view while the next page
    /// loads, then fade it out once that page is ready (with a safety timeout).
    private var frozen: UIView?
    func freeze() {
        guard frozen == nil, window != nil, let snap = snapshotView(afterScreenUpdates: false) else { return }
        snap.frame = frame
        snap.isUserInteractionEnabled = false // never blocks touches (the page underneath is loading anyway)
        superview?.insertSubview(snap, aboveSubview: self)
        frozen = snap
        debugLog("freeze (cross-fade start)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self, weak snap] in
            if let snap, self?.frozen === snap { self?.unfreeze() }
        }
    }
    func unfreeze(animated: Bool = true) {
        guard let snap = frozen else { return }
        frozen = nil
        debugLog("unfreeze (cross-fade end)")
        guard animated else { snap.removeFromSuperview(); return }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            snap.alpha = 0
        } completion: { _ in snap.removeFromSuperview() }
    }

    /// Runs once, the first time the view is in a window with a real size.
    var onReady: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshInsets()
        fireReadyIfPossible()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil, lastReported != safeAreaInsets { refreshInsets() }
        fireReadyIfPossible()
    }
    private func fireReadyIfPossible() {
        guard window != nil, bounds.width >= 1, let ready = onReady else { return }
        onReady = nil
        DispatchQueue.main.async(execute: ready)
    }
    private var lastReported: UIEdgeInsets = .zero
}

// MARK: - WebKit delegates

extension AppModel: WKNavigationDelegate, WKUIDelegate {
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // WebKit's page process died (memory pressure, simulator hiccup): reload the page that
        // was on screen instead of leaving a blank one.
        Task { @MainActor in
            guard let page = self.lastPageURL ?? self.currentURL else { return }
            // A page that keeps crashing its process (too heavy for this phone) would reload
            // forever: after two crashes within a minute, say so instead.
            let now = Date()
            self.crashes = self.crashes.filter { now.timeIntervalSince($0) < 60 } + [now]
            if self.crashes.count > 2 {
                debugLog("web content process terminated again; giving up on \(page.absoluteString)")
                self.crashes = []
                self.loadFailed("This page used too much memory and stopped.")
                return
            }
            debugLog("web content process terminated; reloading \(page.absoluteString)")
            self.loadError = nil
            if self.contentShown { (webView as? FullBleedWebView)?.freeze() }
            self.armReadyTimeout()
            self.loadWhenOnScreen(page)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            webView.scrollView.pinchGestureRecognizer?.isEnabled = false
            self.commitPendingSave() // in case the page never sends its ready signal
            self.trackHistory()
            if webView.url?.scheme?.lowercased() != "about" { self.armReadyFallback() }
            self.pageDidLoad()
        }
    }

    /// Cancelled loads (a newer tap, a swipe that went nowhere) and "frame load interrupted"
    /// (downloads, files the page can't show) aren't failures: the current page stays.
    nonisolated private static func isBenign(_ ns: NSError) -> Bool {
        ns.code == NSURLErrorCancelled || (ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 204))
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        debugLog("didFail: \(ns.code) \(ns.localizedDescription)")
        Task { @MainActor in
            if Self.isBenign(ns) || self.contentShown { self.navigationEnded() } else { self.loadFailed(ns.localizedDescription) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        debugLog("didFailProvisional: \(ns.code) \(ns.localizedDescription)")
        Task { @MainActor in
            if Self.isBenign(ns) { self.navigationEnded() } else { self.loadFailed(ns.localizedDescription) }
        }
    }

    /// Links the web view can't show (tel:, mailto:, sms:, App Store…) go to iOS, a
    /// vercelsim:// link opens here, and the navigation type is noted for the cross-fade.
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        MainActor.assumeIsolated {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.allow) }
            // Only a link the user actually tapped, in the page itself, may leave the web view:
            // a script or an iframe can't open other apps or join this phone to a push room.
            let tapped = navigationAction.navigationType == .linkActivated && (navigationAction.targetFrame?.isMainFrame ?? true)
            if scheme == "vercelsim" {
                decisionHandler(.cancel)
                if PushHub.invite(from: url.absoluteString) != nil, !tapped {
                    debugLog("room invite from page script ignored")
                    return
                }
                self.openIncoming(url)
                return
            }
            if !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) {
                decisionHandler(.cancel)
                guard tapped else { debugLog("\(scheme): link not tapped; ignored"); return }
                debugLog("handing \(scheme): link to iOS")
                UIApplication.shared.open(url)
                return
            }
            if navigationAction.targetFrame?.isMainFrame ?? true { self.pendingNavigationType = navigationAction.navigationType }
            decisionHandler(.allow)
        }
    }

    /// A navigation the page started itself (iteration switch, link, location.href): hold the
    /// current screen and cross-fade when the new one is ready.
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            let type = self.pendingNavigationType
            self.pendingNavigationType = .other
            guard let url = webView.url ?? webView.backForwardList.currentItem?.url, url.scheme != "about",
                  self.contentShown, !self.lockVisible else { return }
            self.armReadyTimeout()
            // Back / forward (the edge swipe): WebKit draws its own transition from snapshots.
            // Freezing here would capture the half-swiped screen and could hold it frozen.
            guard type != .backForward else { return }
            (webView as? FullBleedWebView)?.freeze()
        }
    }

    /// Notes the main frame's HTTP status, so a 404 / 500 page isn't saved as a link.
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        MainActor.assumeIsolated {
            if navigationResponse.isForMainFrame {
                self.lastHTTPStatus = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
            }
            decisionHandler(.allow)
        }
    }

    // target=_blank / window.open stay inside the phone, like a home-screen web app.
    // WebKit calls its UI delegate on the main thread.
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            // window.open(url) opens in place; window.open() with no URL (to be filled in
            // later) would blank the prototype, so it's ignored.
            if let url = navigationAction.request.url, !url.absoluteString.isEmpty, url.scheme?.lowercased() != "about" {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }
}
