import Foundation
import CryptoKit
import UIKit

// Links pushed from the web (Vercel Sim Push, vercel-sim-push/ in the workspace).
//
// A room is a random 128-bit secret, shared by the browsers that push and the phones that
// scanned its code. Everyone in it uses one topic on the ntfy.sh relay, and every message
// is sealed with AES-256-GCM, so the relay only sees ciphertext:
//   topic = "vsim_" + hex(sha256("vercelsim-topic:" + secret)).prefix(40)
//   key   = sha256("vercelsim-key:" + secret)
//   wire  = "vs1." + base64url(nonce ‖ ciphertext ‖ tag)        (CryptoKit's `combined`)
// The web side (app.js) speaks exactly the same thing; keep the two in step.
//
// While the app is in the foreground it holds one streaming request per room; a push lands
// in about a second. In the background nothing runs (true remote push needs APNs and a paid
// developer account); on the way back, the stream resumes from the last message it saw, so
// pushes sent meanwhile (the relay keeps them 12 hours) still arrive.

struct PushRoom: Codable, Identifiable, Equatable {
    var secret: String
    var name: String
    var joinedAt: Date
    /// The relay's id of the last message handled; the stream resumes after it.
    var lastId: String?
    var id: String { secret }
}

struct PushInvite: Equatable {
    let secret: String
    let name: String
}

/// One message in a room (see app.js for the full list). Optional fields are left out of
/// the JSON when nil.
struct PushEnvelope: Codable {
    var t: String
    var id: String?
    var url: String?
    var title: String?
    var open: Bool?
    var to: [String]?
    var from: String?
    var at: Double?
    var dev: String?
    var name: String?
    var model: String?
    var app: String?
    var push: String?
    var state: String?
    /// The phone's platform in a hello: "iOS" here, "Android" from the Android app.
    var os: String?
}

/// A link received from the web page, for the lock screen's "Pushed from web" card.
struct PushedLink: Codable, Identifiable, Equatable {
    var id: String          // the push id
    var url: String
    var title: String?
    var from: String?
    var room: String?       // room name
    var at: Date
    var roomID: String? = nil   // the room's secret (for filtering by room)
}

/// The card that drops in from the top when something arrives.
struct PushNotice: Identifiable, Equatable {
    enum Kind: Equatable { case opening, saved, joined }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    var url: String? = nil
    var room: String? = nil
    var pushId: String? = nil
}

@MainActor
final class PushHub: ObservableObject {
    enum Link: Equatable { case connecting, live, offline }

    static let relay = "https://ntfy.sh"
    /// Where the push page is hosted (repo saswata2002/vercel-link-push), shown in Options.
    static let webAddress: String? = "vercel-link-push.vercel.app"
    /// The install directory (the push page's /api/devices): the deployed page, plus the local
    /// dev server in debug builds (the simulator reaches the Mac at localhost), so both list it.
    static var registryURLs: [URL] {
        var urls = webAddress.flatMap { URL(string: "https://\($0)/api/devices") }.map { [$0] } ?? []
        #if DEBUG
        if let local = URL(string: "http://localhost:8153/api/devices") { urls.append(local) }
        #endif
        return urls
    }
    /// Pushes older than this when they reach the phone (it was away) are saved, not opened.
    static let autoOpenWindow: TimeInterval = 10 * 60

    @Published private(set) var rooms: [PushRoom] = []
    @Published private(set) var links: [String: Link] = [:]
    @Published var notice: PushNotice?
    /// Recently received pushes, newest first (one per link).
    @Published private(set) var received: [PushedLink] = []
    /// At least one room's stream is connected.
    var isLive: Bool { links.values.contains(.live) }
    /// How this phone is listed on the web ("Sas's iPhone"); the model name until edited.
    @Published var deviceName: String {
        didSet {
            let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? nil : trimmed, forKey: "pushDeviceName")
            helloSoon()
        }
    }
    let deviceId: String
    let model: String
    weak var app: AppModel?

    private let defaults = UserDefaults.standard
    private var listeners: [String: Task<Void, Never>] = [:]
    private var heartbeat: Task<Void, Never>?
    private var helloDebounce: Task<Void, Never>?
    private var openDebounce: Task<Void, Never>?
    private var seenPushes: [String]
    private var lastHello: [String: Date] = [:]
    private var running = false
    private var keys: [String: (topic: String, key: SymmetricKey)] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 100      // the relay sends a keepalive every 45 s
        c.timeoutIntervalForResource = 24 * 3600
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    init(model: String) {
        self.model = model
        if let id = defaults.string(forKey: "pushDeviceId") {
            deviceId = id
        } else {
            deviceId = Self.randomId(9)
            defaults.set(deviceId, forKey: "pushDeviceId")
        }
        deviceName = defaults.string(forKey: "pushDeviceName") ?? model
        if defaults.object(forKey: "installedAt") == nil { defaults.set(Date(), forKey: "installedAt") }
        seenPushes = defaults.stringArray(forKey: "pushSeen") ?? []
        if let data = defaults.data(forKey: "pushRooms"), let saved = try? JSONDecoder().decode([PushRoom].self, from: data) {
            rooms = saved
        }
        if let data = defaults.data(forKey: "pushReceived"), let saved = try? JSONDecoder().decode([PushedLink].self, from: data) {
            received = saved
        }
    }

    var displayName: String {
        let t = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? model : String(t.prefix(40))
    }

    /// The device shown under the name on the web ("iPhone 17 Pro", "Pixel 9"); this
    /// phone's model unless edited.
    @Published var deviceLabel: String = UserDefaults.standard.string(forKey: "pushDeviceLabel") ?? "" {
        didSet {
            let t = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(t.isEmpty ? nil : t, forKey: "pushDeviceLabel")
            helloSoon()
        }
    }
    var shownModel: String {
        let t = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? model : String(t.prefix(40))
    }

    /// The platform badge on the web: "iOS" or "Android".
    static let platforms = ["iOS", "Android"]
    @Published var platform: String = UserDefaults.standard.string(forKey: "pushPlatform") ?? "iOS" {
        didSet {
            defaults.set(platform, forKey: "pushPlatform")
            helloSoon()
        }
    }

    // MARK: lifecycle

    /// The app is in the foreground: listen to every room and say hello.
    func start() {
        guard !running else { return }
        running = true
        debugLog("push: start (\(rooms.count) room\(rooms.count == 1 ? "" : "s"))")
        for room in rooms { connect(room.secret) }
        for room in rooms { hello(room.secret) }
        register()
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8 * 60 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                for room in self.rooms { self.hello(room.secret, force: true) }
            }
        }
    }

    /// Going to the background: tell the rooms, then stop listening.
    func stop() {
        guard running else { return }
        running = false
        debugLog("push: stop")
        heartbeat?.cancel()
        listeners.values.forEach { $0.cancel() }
        listeners.removeAll()
        for room in rooms { links[room.secret] = .offline }
        guard !rooms.isEmpty else { return }
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "push-away") { UIApplication.shared.endBackgroundTask(task) }
        let sends = rooms.map { room in send(PushEnvelope(t: "away", at: Self.now, dev: deviceId), to: room.secret) }
        Task {
            for s in sends { await s.value }
            UIApplication.shared.endBackgroundTask(task)
        }
        lastHello.removeAll()
    }

    // MARK: rooms

    /// A room invite from the web: `vercelsim://pair?room=…&name=…` (its QR code) or the
    /// https invite link (`…/#join=…&n=…`) pasted or shared into the app.
    static func invite(from raw: String) -> PushInvite? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return nil }
        var items: [URLQueryItem] = []
        var secretKey = "room", nameKey = "name"
        if scheme == "vercelsim", url.host?.lowercased() == "pair" {
            items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        } else if scheme == "http" || scheme == "https", let fragment = url.fragment, fragment.contains("join=") {
            var c = URLComponents()
            c.percentEncodedQuery = fragment
            items = c.queryItems ?? []
            secretKey = "join"; nameKey = "n"
        } else {
            return nil
        }
        guard let secret = items.first(where: { $0.name == secretKey })?.value,
              secret.range(of: #"^[A-Za-z0-9_-]{16,64}$"#, options: .regularExpression) != nil else { return nil }
        let name = (items.first(where: { $0.name == nameKey })?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return PushInvite(secret: secret, name: name.isEmpty ? "Vercel Sim room" : String(name.prefix(40)))
    }

    func join(_ invite: PushInvite) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let i = rooms.firstIndex(where: { $0.secret == invite.secret }) {
            rooms[i].name = invite.name
            persist()
            show(PushNotice(kind: .joined, title: "Already in \(invite.name)", detail: "Links pushed to this room open here."))
            hello(invite.secret, force: true)
            return
        }
        debugLog("push: joined \(invite.name)")
        // Start from now: older pushes in the room were meant for the phones there then.
        rooms.append(PushRoom(secret: invite.secret, name: invite.name, joinedAt: Date(), lastId: nil))
        persist()
        if running { connect(invite.secret) }
        hello(invite.secret, force: true)
        show(PushNotice(kind: .joined, title: "Joined \(invite.name)", detail: "Links pushed to this room open here."))
    }

    func leave(_ room: PushRoom) {
        debugLog("push: left \(room.name)")
        _ = send(PushEnvelope(t: "bye", at: Self.now, dev: deviceId), to: room.secret)
        listeners[room.secret]?.cancel()
        listeners[room.secret] = nil
        links[room.secret] = nil
        rooms.removeAll { $0.secret == room.secret }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rooms) { defaults.set(data, forKey: "pushRooms") }
    }

    // MARK: listening

    private func connect(_ secret: String) {
        guard listeners[secret] == nil else { return }
        listeners[secret] = Task { [weak self] in
            var backoff: Double = 1
            while !Task.isCancelled {
                guard let self, let room = self.rooms.first(where: { $0.secret == secret }) else { return }
                let (topic, _) = self.derived(secret)
                // First connection after joining: only what's new. After that: resume.
                let since = room.lastId ?? "\(Int(room.joinedAt.timeIntervalSince1970))"
                guard let url = URL(string: "\(Self.relay)/\(topic)/json?since=\(since)") else { return }
                if self.links[secret] != .live { self.links[secret] = .connecting }
                do {
                    let (bytes, response) = try await self.session.bytes(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await line in bytes.lines {
                        // Only a real message proves the stream works: a relay that sends
                        // "open" and then drops would otherwise be retried every second.
                        if line.contains("\"event\":\"message\"") { backoff = 1 }
                        self.receive(line, secret: secret)
                    }
                } catch {
                    if Task.isCancelled { return }
                    debugLog("push: stream ended (\(error.localizedDescription)); retrying in \(Int(backoff)) s")
                }
                self.links[secret] = .offline
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 20)
            }
        }
    }

    private struct RelayEvent: Decodable {
        let id: String
        let time: Double
        let event: String
        let message: String?
    }

    private func receive(_ line: String, secret: String) {
        guard let data = line.data(using: .utf8), let ev = try? JSONDecoder().decode(RelayEvent.self, from: data) else { return }
        if links[secret] != .live { links[secret] = .live; debugLog("push: live in \(rooms.first { $0.secret == secret }?.name ?? "?")") }
        guard ev.event == "message", let i = rooms.firstIndex(where: { $0.secret == secret }) else { return }
        rooms[i].lastId = ev.id
        persist()
        guard let text = ev.message, let env = unseal(text, secret: secret) else { return }
        handle(env, secret: secret, relayTime: ev.time)
    }

    private func handle(_ env: PushEnvelope, secret: String, relayTime: Double) {
        switch env.t {
        case "push":
            guard let id = env.id, let raw = env.url, let url = AppModel.normalize(raw) else { return }
            if let to = env.to, !to.contains(deviceId) { return }
            guard !seenPushes.contains(id) else { return }
            seenPushes.append(id)
            if seenPushes.count > 200 { seenPushes.removeFirst(seenPushes.count - 200) }
            defaults.set(seenPushes, forKey: "pushSeen")
            ack(id, "received", secret: secret)
            let age = Date().timeIntervalSince1970 - relayTime
            let from = env.from.map { "From \($0)" } ?? "Pushed"
            let title = (env.title?.isEmpty == false ? env.title : nil) ?? AppModel.display(url.absoluteString)
            let detail = "\(from) · \(url.host ?? "")"
            debugLog("push: \(url.absoluteString) from \(env.from ?? "?") (open \(env.open ?? false), \(Int(age)) s old)")
            if let name = env.title, !name.isEmpty { pendingTitles[url.absoluteString] = name }
            record(PushedLink(id: id, url: url.absoluteString, title: env.title?.isEmpty == false ? env.title : nil,
                              from: env.from, room: rooms.first { $0.secret == secret }?.name, at: Date(), roomID: secret))
            if env.open == true, age < Self.autoOpenWindow {
                // A teammate sent it on purpose: it goes in the directory straight away (every
                // one of a burst, not only the one that ends up opening).
                app?.directory.save(url)
                applyTitle(for: url)
                // Several arriving at once (back from the background): one haptic, and the
                // newest one opens.
                if openDebounce == nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                show(PushNotice(kind: .opening, title: title, detail: detail, url: url.absoluteString, room: secret, pushId: id))
                openDebounce?.cancel()
                openDebounce = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.openDebounce = nil
                    self.app?.open(url.absoluteString)
                    self.ack(id, "opened", secret: secret)
                }
            } else {
                app?.directory.save(url)
                applyTitle(for: url)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                show(PushNotice(kind: .saved, title: title, detail: detail, url: url.absoluteString, room: secret, pushId: id))
            }
        case "ping":
            // Spread the replies out a little when a room has many phones.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64.random(in: 0...900_000_000))
                self?.hello(secret, force: true)
            }
        case "room":
            if let name = env.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
               let i = rooms.firstIndex(where: { $0.secret == secret }) {
                rooms[i].name = String(name.prefix(40))
                persist()
            }
        default:
            break   // hellos, acks and goodbyes are for the web page
        }
    }

    private func record(_ link: PushedLink) {
        received.removeAll { $0.url == link.url }
        received.insert(link, at: 0)
        if received.count > 20 { received.removeLast(received.count - 20) }
        if let data = try? JSONEncoder().encode(received) { defaults.set(data, forKey: "pushReceived") }
    }

    func clearReceived() {
        received = []
        defaults.removeObject(forKey: "pushReceived")
    }

    /// A name sent with the push wins over the page's own title, the way a rename does.
    private var pendingTitles: [String: String] = [:]
    private func applyTitle(for url: URL) {
        guard let name = pendingTitles[url.absoluteString], let app,
              let link = app.directory.links.first(where: { AppModel.sameDocument(URL(string: $0.url), url) }) else { return }
        if link.name == nil { app.directory.update(link, name: name, url: url) }
        pendingTitles[url.absoluteString] = nil
    }

    /// The notice was tapped: open what it brought.
    func openNotice(_ n: PushNotice) {
        notice = nil
        guard let url = n.url else { return }
        app?.open(url)
        if let id = n.pushId, let room = n.room, n.kind == .saved { ack(id, "opened", secret: room) }
    }

    private func show(_ n: PushNotice) {
        notice = n
        let id = n.id
        let hold: Double = n.kind == .saved ? 8 : 3.6
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            if self?.notice?.id == id { self?.notice = nil }
        }
    }

    // MARK: sending

    private func hello(_ secret: String, force: Bool = false) {
        if !force, let last = lastHello[secret], Date().timeIntervalSince(last) < 60 { return }
        lastHello[secret] = Date()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        _ = send(PushEnvelope(t: "hello", at: Self.now, dev: deviceId, name: displayName, model: shownModel, app: version, os: platform), to: secret)
    }

    /// After the name is edited: one hello per room once typing stops.
    private func helloSoon() {
        helloDebounce?.cancel()
        helloDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled, self.running else { return }
            for room in self.rooms { self.hello(room.secret, force: true) }
            self.register()
        }
    }

    // MARK: install directory

    /// Tell the install directory this phone has the app: on launch (at most every 6 hours)
    /// and straight away when its name or the app version changes. Rooms don't matter here.
    private func register() {
        let urls = Self.registryURLs
        guard !urls.isEmpty else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        // The directory address is part of it, so a new one (the page moved) checks in straight away.
        let signature = "\(displayName)|\(shownModel)|\(platform)|\(version)|\(urls[0].host ?? "")"
        if defaults.string(forKey: "registrySignature") == signature,
           let last = defaults.object(forKey: "registeredAt") as? Date, Date().timeIntervalSince(last) < 6 * 3600 { return }
        if defaults.object(forKey: "installedAt") == nil { defaults.set(Date(), forKey: "installedAt") }
        let installed = (defaults.object(forKey: "installedAt") as? Date ?? Date()).timeIntervalSince1970 * 1000
        let body: [String: Any] = ["id": deviceId, "name": displayName, "model": shownModel, "os": platform, "app": version, "installedAt": installed.rounded()]
        let payload = try? JSONSerialization.data(withJSONObject: body)
        let defaults = defaults
        let session = session
        Task {
            var landed = false
            for url in urls {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = payload
                do {
                    let (_, response) = try await session.data(for: req)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    debugLog("registry \(url.host ?? ""): \(code)")
                    // The deployed directory (the first) is the one that counts for the 6 h throttle.
                    if url == urls.first, (200..<300).contains(code) { landed = true }
                } catch {
                    debugLog("registry \(url.host ?? "") failed: \(error.localizedDescription)")
                }
            }
            if landed {
                defaults.set(signature, forKey: "registrySignature")
                defaults.set(Date(), forKey: "registeredAt")
            }
        }
    }

    private func ack(_ push: String, _ state: String, secret: String) {
        _ = send(PushEnvelope(t: "ack", at: Self.now, dev: deviceId, push: push, state: state), to: secret)
    }

    @discardableResult
    private func send(_ env: PushEnvelope, to secret: String) -> Task<Void, Never> {
        let (topic, key) = derived(secret)
        let session = session
        return Task {
            guard let body = Self.seal(env, key: key), let url = URL(string: "\(Self.relay)/\(topic)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = Data(body.utf8)
            do {
                let (_, response) = try await session.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code != 200 { debugLog("push: send \(env.t) → HTTP \(code)") }
            } catch {
                debugLog("push: send \(env.t) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: crypto

    private func derived(_ secret: String) -> (topic: String, key: SymmetricKey) {
        if let k = keys[secret] { return k }
        let topicHash = SHA256.hash(data: Data("vercelsim-topic:\(secret)".utf8)).map { String(format: "%02x", $0) }.joined()
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data("vercelsim-key:\(secret)".utf8))))
        let k = (topic: "vsim_" + topicHash.prefix(40), key: key)
        keys[secret] = k
        return k
    }

    private func unseal(_ text: String, secret: String) -> PushEnvelope? {
        guard text.hasPrefix("vs1."), let data = Data(base64URL: String(text.dropFirst(4))),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: derived(secret).key) else { return nil }
        return try? JSONDecoder().decode(PushEnvelope.self, from: plain)
    }

    nonisolated private static func seal(_ env: PushEnvelope, key: SymmetricKey) -> String? {
        guard let json = try? JSONEncoder().encode(env), let box = try? AES.GCM.seal(json, using: key), let combined = box.combined else { return nil }
        return "vs1." + combined.base64URL
    }

    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    private static func randomId(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URL
    }
}

extension Data {
    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        self.init(base64Encoded: b)
    }

    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
