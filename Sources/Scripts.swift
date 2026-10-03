import Foundation

/// JavaScript run inside the prototype. Same detection as the Mac app (renderer.js).
enum Scripts {
    static let mark = "data-vercel-sim-switcher"

    /// Hides the page's own iteration picker once it has been found and marked.
    static let hideSwitcherStyle = #"""
    (() => {
      const add = () => {
        if (document.getElementById('vercel-sim-switcher-hide')) return;
        const st = document.createElement('style');
        st.id = 'vercel-sim-switcher-hide';
        // touch-action: manipulation turns off WebKit's double-tap-to-zoom (and its tap delay).
        // Feel like an app, not a web page: no text selection, no long-press callout or
        // grey tap flash. Text fields keep selection so typing and editing still work.
        st.textContent = '[data-vercel-sim-switcher] { display: none !important; } html { touch-action: manipulation; -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }'
          + ' *, *::before, *::after { -webkit-user-select: none !important; user-select: none !important; -webkit-touch-callout: none !important; -webkit-tap-highlight-color: transparent !important; }'
          + ' input, textarea, select, [contenteditable]:not([contenteditable="false"]), [contenteditable]:not([contenteditable="false"]) * { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; }';
        (document.head || document.documentElement).appendChild(st);
      };
      if (document.documentElement) add(); else document.addEventListener('DOMContentLoaded', add);
    })();
    """#

    /// Haptics bridge, injected into every frame at document start (see HapticEngine):
    /// a working `navigator.vibrate` (WebKit on iOS has none), a watcher for the hidden
    /// `<input type="checkbox" switch>` trick, and `window.VercelSim.haptic(kind)`.
    /// `webkit.messageHandlers.haptic` itself is registered natively.
    static let haptics = #"""
    (() => {
      const h = window.webkit && window.webkit.messageHandlers;
      if (!h || !h.__vsVibrate || window.__vsHaptics) return;
      window.__vsHaptics = true;
      if (typeof navigator.vibrate !== 'function') {
        const vibrate = function (pattern) {
          let p = Array.isArray(pattern) ? pattern : [pattern];
          p = p.map((v) => Math.max(0, Number(v) || 0)).slice(0, 32);
          try { h.__vsVibrate.postMessage(p); } catch (_) {}
          return true;
        };
        try { Object.defineProperty(Navigator.prototype, 'vibrate', { value: vibrate, configurable: true, writable: true }); }
        catch (_) { navigator.vibrate = vibrate; }
      }
      // iOS switch haptic trick: a native <input type=checkbox switch> toggled (often by .click() on its label).
      document.addEventListener('change', (e) => {
        const t = e.target;
        if (t && t.tagName === 'INPUT' && t.type === 'checkbox' && t.hasAttribute('switch')) {
          try { h.__vsSwitch.postMessage(1); } catch (_) {}
        }
      }, true);
      window.VercelSim = Object.assign(window.VercelSim || {}, {
        native: true,
        haptic(kind = 'light', intensity) { try { h.haptic.postMessage(intensity == null ? String(kind) : { type: String(kind), intensity }); } catch (_) {} },
      });
    })();
    """#

    /// Tells the app when the first complete screen is painted, so it can reveal the page
    /// without showing it half-built: the load event (capped at 2.5 s after the DOM is
    /// ready), web fonts, and every image on screen loaded *and decoded*, then two frames.
    static let readySignal = #"""
    (() => {
      const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.__vsReady;
      if (!h || window.__vsReadyArmed) return;
      window.__vsReadyArmed = true;
      const cap = (p, ms) => Promise.race([p, new Promise((r) => setTimeout(r, ms))]);
      const loaded = new Promise((r) => (document.readyState === 'complete' ? r() : addEventListener('load', r, { once: true })));
      const domReady = new Promise((r) => (document.readyState !== 'loading' ? r() : document.addEventListener('DOMContentLoaded', r, { once: true })));
      const onScreenImages = () => [...document.images].filter((i) => {
        const r = i.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth;
      });
      const frames = (n) => new Promise((r) => { const f = () => (--n <= 0 ? r() : requestAnimationFrame(f)); requestAnimationFrame(f); });
      domReady
        .then(() => cap(loaded, 2500))
        .then(() => cap(document.fonts ? document.fonts.ready : Promise.resolve(), 500))
        .then(() => cap(Promise.all(onScreenImages().map((i) => (i.decode ? i.decode().catch(() => {}) : 0))), 700))
        .then(() => frames(2))
        .then(() => { try { h.postMessage({ href: location.href, why: document.readyState }); } catch (_) {} });
    })();
    """#

    /// Locks the prototype to the device. The page lays out at `width` CSS px (375, the
    /// design base) and is scaled by `scale` to fill the screen, with zoom pinned at that
    /// scale, so double-tap or pinch can't zoom in or out. Rewrites the page's own viewport
    /// tag as soon as it appears, keeping keys this doesn't own (interactive-widget, …).
    static func viewportLock(width: String, scale: CGFloat) -> String {
        let s = String(format: "%.5f", Double(scale))
        return """
        (() => {
          const OWN = /^(width|height|initial-scale|minimum-scale|maximum-scale|user-scalable|viewport-fit|shrink-to-fit)$/i;
          const want = (c) => {
            const keep = String(c || '').split(',').map((x) => x.trim()).filter((x) => x && !OWN.test(x.split('=')[0].trim()));
            return ['width=\(width)', 'initial-scale=\(s)', 'minimum-scale=\(s)', 'maximum-scale=\(s)', 'user-scalable=no', 'viewport-fit=cover', ...keep].join(', ');
          };
          const fixAll = () => {
            const metas = document.querySelectorAll('meta[name="viewport" i]');
            if (!metas.length) {
              const m = document.createElement('meta');
              m.name = 'viewport';
              (document.head || document.documentElement).appendChild(m);
              return fixAll();
            }
            metas.forEach((m) => { const c = want(m.getAttribute('content')); if (m.getAttribute('content') !== c) m.setAttribute('content', c); });
          };
          fixAll();
          new MutationObserver(fixAll).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ['content', 'name'] });
        })();
        """
    }

    /// Finds a "design variations" picker: an aria-label / class mentioning variation,
    /// variant, iteration or version, else a fixed-position group of numbered buttons.
    /// Marks it (so the style above hides it) and returns its options.
    static let scanSwitcher = #"""
    (() => {
      const MARK = 'data-vercel-sim-switcher';
      const OPT = /^\s*(?:v|var(?:iant)?|opt(?:ion)?|it(?:eration)?|version)?\s*\d{1,2}\s*$/i;
      const text = (b) => (b.textContent || '').trim();
      const isOpt = (b) => OPT.test(text(b));
      const controls = (el) => [...el.querySelectorAll('button, [role="button"], [role="tab"], [role="radio"], a[href]')];
      const hasOpts = (el) => controls(el).filter(isOpt).length >= 2;
      let box = document.querySelector('[' + MARK + ']');
      if (!box) {
        const named = document.querySelectorAll('[aria-label*="variation" i], [aria-label*="variant" i], [aria-label*="iteration" i], [aria-label*="version" i], [id*="vswitch" i], [class*="vswitch" i], [class*="variant" i], [class*="iteration" i], [id*="variant" i], [id*="iteration" i], [data-variant-switcher]');
        box = [...named].find(hasOpts) || null;
      }
      if (!box) {
        outer: for (const b of document.querySelectorAll('button, [role="button"]')) {
          if (!isOpt(b)) continue;
          for (let p = b.parentElement; p && p !== document.body; p = p.parentElement) {
            if (getComputedStyle(p).position === 'fixed') { if (hasOpts(p)) { box = p; break outer; } break; }
          }
        }
      }
      if (!box) return null;
      box.setAttribute(MARK, '');
      const on = (b) => b.getAttribute('aria-pressed') === 'true' || b.getAttribute('aria-selected') === 'true' || b.getAttribute('aria-checked') === 'true' ||
        (b.hasAttribute('aria-current') && b.getAttribute('aria-current') !== 'false') ||
        /(^|\s)(is-)?(active|selected|current|on)(\s|$)/.test(typeof b.className === 'string' ? b.className : '');
      const items = [];
      controls(box).forEach((b, i) => {
        const meta = [b.title, b.getAttribute('aria-label'), b.id, typeof b.className === 'string' ? b.className : ''].join(' ');
        if (isOpt(b)) items.push({ i, kind: 'option', text: text(b).replace(/\D+/g, '') || text(b), selected: on(b) });
        else if (/reset|restart|start again|reload/i.test(meta)) items.push({ i, kind: 'reset', text: b.title || b.getAttribute('aria-label') || 'Reset', selected: false });
        else {
          // Any other control in the picker (e.g. "Spec Sheet") — keep it, with its name.
          const name = (b.getAttribute('data-tip') || b.title || b.getAttribute('aria-label') || text(b) || 'Action').split(/\s+[—–-]\s+/)[0].trim();
          items.push({ i, kind: 'action', text: name, selected: false });
        }
      });
      return { label: box.getAttribute('aria-label') || '', items };
    })()
    """#

    /// Presses control `index` of the marked picker, so the page's own logic runs.
    static func press(index: Int) -> String {
        """
        (() => {
          const box = document.querySelector('[\(mark)]');
          const c = box && box.querySelectorAll('button, [role="button"], [role="tab"], [role="radio"], a[href]')[\(index)];
          if (c) c.click();
          return !!c;
        })()
        """
    }
}
