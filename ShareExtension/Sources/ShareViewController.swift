import UIKit
import UniformTypeIdentifiers

/// "Vercel Sim" in the share sheet. iOS doesn't let an app claim another company's https links
/// (vercel.app would have to list it), so a link tapped in WhatsApp, Gmail or Google Chat opens
/// in Safari; sharing it — or long-pressing it and choosing Share — hands it here instead. This
/// takes the link exactly as shared (path, query and #fragment), opens
/// vercelsim://open?url=<link> and the app loads that preview. No UI of its own.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await run() }
    }

    private func run() async {
        guard let link = await sharedLink(),
              var c = URLComponents(string: "vercelsim://open") else { return finish(error: true) }
        // Encode "&", "=", "#", "?" and "+" too (queryItems wouldn't), so the shared link's own
        // query and fragment survive as one value.
        c.percentEncodedQuery = "url=" + (link.addingPercentEncoding(withAllowedCharacters: Self.valueAllowed) ?? link)
        guard let url = c.url, openHostApp(url) else { return finish(error: true) }
        finish(error: false)
    }

    private static let valueAllowed: CharacterSet = {
        var s = CharacterSet.urlQueryAllowed
        s.remove(charactersIn: "&=#?+")
        return s
    }()

    /// The first http(s) link among the shared items: a URL item first, then any text.
    private func sharedLink() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               ["http", "https"].contains(u.scheme?.lowercased() ?? "") { return u.absoluteString }
        }
        var texts = items.compactMap { $0.attributedContentText?.string }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { texts.append(t) }
        }
        for t in texts {
            if let r = t.range(of: #"https?://[^\s<>"']+"#, options: [.regularExpression, .caseInsensitive]) {
                return String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
            }
        }
        return nil
    }

    /// Extensions can't call UIApplication.open directly; the app object is still on the
    /// responder chain, so send it openURL:options:completionHandler: there.
    private func openHostApp(_ url: URL) -> Bool {
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var r: UIResponder? = self
        while let current = r {
            if current.isKind(of: UIApplication.self), current.responds(to: sel) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
                let f = unsafeBitCast(current.method(for: sel), to: Open.self)
                f(current, sel, url as NSURL, NSDictionary(), nil)
                return true
            }
            r = current.next
        }
        return false
    }

    private func finish(error: Bool) {
        if error {
            extensionContext?.cancelRequest(withError: NSError(domain: "VercelSim", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "That share doesn't contain a link."]))
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
