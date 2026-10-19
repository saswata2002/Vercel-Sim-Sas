# Vercel Sim (iPhone)

The iPhone companion to **Vercel Mac Sim** (`../iphone-sim`). Open a Vercel prototype
full-screen on an iPhone or in the iOS Simulator. It runs in WebKit, Safari's engine,
with real touch, native scrolling and the device's own refresh rate.

## Run

Open `VercelSim.xcodeproj` in Xcode and press Run, or from the terminal:

```bash
xcodebuild -project VercelSim.xcodeproj -scheme VercelSim -destination 'platform=iOS Simulator,name=iPhone 13 mini' -derivedDataPath build build
```

Then install `build/Build/Products/Debug-iphonesimulator/VercelSim.app` with
`xcrun simctl install booted …` and launch `com.prototype.vercelsim`.

Simulator builds don't need signing. To run on a real iPhone, choose your team under
Signing & Capabilities.

## Using it

| | |
|---|---|
| Link widget | The **Open a prototype** card under the clock. Paste (press and hold in the field) or type a Vercel link and tap the arrow (or Go) to load it. The ✕ clears the field; an invalid link shakes the card and says so. |
| Paste mode | Tapping the link field focuses it: the Link Directory, Pushed from web and Quick tour blur, drift down and fade away, the *Open a prototype* card springs down to sit just above the keyboard (measured, so it fits every iPhone), and a back arrow appears beside its title. Back (or tapping the canvas) closes the keyboard and brings everything back. It holds while a pasted link is opening. |
| Link Directory | The card under *Open a prototype*. Every link you submit (widget or options sheet) is saved automatically once its page loads. Typos, unreachable servers and HTTP error pages (404, 500…) are never saved: newest first, no duplicates, titled from the page once it loads (e.g. *noon — Home*). Tap a row to open it. Swipe left to delete: a short swipe shows Delete, a long one deletes at once. Swipe right to edit: a short swipe shows Edit, a long one opens the editor. There you can rename the link, and change its URL only if you edit it. Your name is never replaced by the page title, and clearing it brings the title back. Press and hold for Edit / Copy Link / Remove. File links (images, PDFs…) are skipped. Up to **5 rows** show at once; more scroll inside the card, feathering out at the edges. |
| How-to guide | The **Quick tour** pill at the foot of the lock screen opens a 5-page guide, one animated picture and one line each: paste a link, saved links (swipe to edit/delete), swipe up to return, two-finger double-tap for Options, switching iterations. It plays through by itself (5 s a page, stopping on the last); swipe or tap a dot to jump. The one button, **Got It**, closes it from any page; there is no Skip or Next. It only opens from that button, never by itself. |
| Pushed from web | A lock-screen card under the Link Directory lists links received from the Vercel Sim Push page (newest first, up to 2 shown, 20 kept), with who sent them and when, and the room's status (Live / Connecting / Offline). Tap one to open it; press and hold to copy it or clear the list. With no room joined it offers **Set up**, which opens a small **Join a room** sheet: the room's invite link (Paste button, filled in automatically when one is on the clipboard), your name, the device name and the platform (iOS / Android) shown on the web, and **Join room**. It shrinks to the latest push on short screens. |
| Floating sheets | Options, Edit link and the guide are floating cards: inset 10 pt from the sides and bottom, every corner rounded concentric with the display, a hairline border and a soft shadow. No visible handle: drag the top edge down or tap outside to close; they rise above the keyboard. Drawn by the app (`LWFloatingSheet` in Lightweight.swift) rather than the system sheet, whose iOS 26 glass edge doubled the border. |
| Lock screen | The Lightweight UI dark canvas (dot grid) with the cards; no wallpaper, date or time. **Swipe up** resumes the open prototype, or the most recent one. With nothing to open, it shows the panel. |
| Options sheet | **Double-tap with two fingers anywhere** (over a prototype or on the lock screen) to open a bottom sheet with every option. A single-finger double-tap always goes to the prototype. A two-finger press-and-hold or a shake (Simulator: ⌃⌘Z) also opens it. Contents: the iteration selector (numbers, reset and any other controls such as *Spec Sheet*), the address field, Reload, Screenshot (share sheet), Home, recents, status bar, home indicator, 375 scaling, the on-screen iteration pill, Appearance, device details, and Clear cookies & cache. |
| Options over a prototype | A browser-style menu that fits without scrolling: an address pill (back · forward within the prototype · tap the address to type a new link · copy link · reload), the iteration chips and Spec Sheet, tiles for Home / Screenshot / Share / Recents, icon rows for Status bar and Haptics (checkboxes) and Settings. Settings is a second page (home indicator, 375 scaling, iteration pill, Push from the web, Clear cookies & cache). On the lock screen the full Options list is shown instead. |
| Iteration selector | The prototype's own picker (1 · 2 · 3 · 4 · reset · Spec Sheet…) is detected and hidden in the page, then shown in the options sheet. Turn on *Iteration pill on screen* for a floating pill. |
| Device fit (automatic) | The app detects the iPhone (model, screen, scale, safe areas) and locks the page's viewport to `width=375` at a fixed scale of screen width ÷ 375, with `user-scalable=no`. The design lays out at exactly 375 CSS px (including `100vw`), keeps its proportions, and fills the screen. The height follows the device's aspect ratio, and safe areas reach the page as `env(safe-area-inset-*)` in its own px. The page's own viewport tag is rewritten, keeping keys like `interactive-widget`. |
| No zoom | Pinch zoom, double-tap zoom and zoom bounce are all off, so the prototype stays fixed to the screen. Pressing and holding never selects text or shows a callout or link preview, so it feels like an app, not a web page (text fields still select normally). |
| Status bar / home indicator | Hidden over prototypes by default; the lock screen always shows them. |
| Appearance | System / Light / Dark, sets `prefers-color-scheme` for the prototype. |
| Haptics | The prototype's haptics play on the iPhone's Taptic Engine, detected automatically: (1) `window.webkit.messageHandlers.haptic.postMessage(kind)` (also `haptics`, `hapticFeedback`, `vibrate`), with a kind name or `{type, intensity}`; (2) `navigator.vibrate(ms or pattern)`, which iOS WebKit lacks, so the app provides it; (3) toggling a hidden `<input type="checkbox" switch>`. When two channels fire for one moment, it plays once. Options ▸ *Haptics* turns them off. |
| Back / forward | Edge swipe, as in Safari. |
| Debugging | Safari ▸ Develop ▸ (device) inspects the prototype. |

Vercel sign-ins (Deployment Protection) are remembered between launches.

### Opening a prototype

- **First time:** after Enter (or the arrow), the page loads *behind* the lock screen while the arrow becomes a spinner. The reveal starts only once the page's first screen is complete: the load event (capped at 2.5 s), web fonts, and every on-screen image loaded and decoded.
- **The reveal:** the lock screen slides up while the prototype grows from 94 % to full size and its corners square off from the display's own radius, on one critically damped spring (0.52 s). The finished screen is the first frame you see.
- **Opened before:** the reveal starts immediately on a saved snapshot of the prototype's first screen. The live page is swapped in underneath, and the snapshot fades off once the page is ready.
- **Swipe up:** the same reveal, continuing from where your finger lets go.
- **While a prototype is showing:** Reload, iteration switches and links hold the current screen and cross-fade to the new one, never showing a blank page.
- **If a link fails to load:** the widget shakes and shows the error, so you're never dropped onto an error screen.
- **Haptics:** haptics from a page loading behind the lock screen are held back.

### Links from other apps

iOS only hands a website's links to an app when the website lists that app (an
`apple-app-site-association` file on the domain). vercel.app is Vercel's domain, so no app
can take over vercel.app links, and a link tapped in WhatsApp, Gmail or Google Chat opens in
Safari or the in-app browser. Two ways in:

- **Share sheet:** share the link to **Vercel Sim**. In WhatsApp, Gmail and Chat you can
  long-press the link and choose Share; in Safari, use Share. The share extension
  (`ShareExtension/`, target `VercelSimShare`) takes the link exactly as shared, including
  the path, `?query` and `#fragment`. It also works when the share is text with a link in it,
  as WhatsApp sends. It then opens the app on that preview.
- **URL scheme:** `vercelsim://open?url=<percent-encoded link>` or
  `vercelsim://my-app.vercel.app/path?q#f`, from Shortcuts, Notes, a QR code or a web page.

A link that differs from the running prototype only in its query or #fragment loads as a new
preview. The exact same URL just brings the running page back.

```bash
xcrun simctl openurl booted 'vercelsim://open?url=https%3A%2F%2Fmy-app.vercel.app%2F%3Fv%3D2%23top'
```

### Haptics mapping

| From the prototype | iOS haptic |
|---|---|
| `selection`, `tick`, `change`, a switch toggle | selection tick |
| `light`, `tap`, `click` | light impact |
| `medium`, `impact`, `snap`, `bump` | medium impact |
| `heavy`, `thud`; `soft`; `rigid` | heavy / soft / rigid impact |
| `success`, `warning`, `error` | notification haptics |
| `{ type, intensity: 0–1 }` | that impact at that intensity |
| `vibrate(1–6)` / `(7–12)` / `(13–24)` / `(≥25)` ms | selection / light / medium / heavy |
| `vibrate([10, 40, 16])` (two short pulses ≤ 100 ms) | success |
| longer patterns `[on, off, on, …]` | each pulse at its time; `vibrate(0)` cancels |

Pages can also call `window.VercelSim.haptic('success')`, and check `window.VercelSim.native`
to tell they're running in the app. The Simulator has no Taptic Engine, so test haptics on a
physical iPhone; Debug builds log each one as `[VercelSim] haptic: …`.

Not on iPhone, because a phone doesn't need them: the device frame and its finish, zoom,
the device picker and the pointer styles.

The options gesture uses two fingers, so a single-finger double-tap always belongs to the
prototype (the two-finger taps still reach the page, which ignores them on most screens).

### Supported devices (verified)

Every iPhone 12–17 model falls into one of these screen classes. All of them were tested
in the Simulator with `noon-pdp-v2` and `product-upscale.vercel.app`. In every case the
page is exactly 375 CSS px wide with no horizontal overflow, the design frame fills the
viewport, and zoom is locked at the device's scale.

| Screen | Models | Cutout | Page layout | Scale | `env(safe-area-inset)` top / bottom |
|---|---|---|---|---|---|
| 375 × 812 | 12 mini, 13 mini | Notch | 375 × 812 | 1 | 50 / 34 |
| 390 × 844 | 12, 12 Pro, 13, 13 Pro, 14, 16e, 17e | Notch | 375 × 812 | 1.040 | 45.2 / 32.7 |
| 428 × 926 | 12 Pro Max, 13 Pro Max, 14 Plus | Notch | 375 × 811 | 1.141 | 41.2 / 29.8 |
| 393 × 852 | 14 Pro, 15, 15 Pro, 16 | Dynamic Island | 375 × 813 | 1.048 | 56.3 / 32.4 |
| 430 × 932 | 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus | Dynamic Island | 375 × 813 | 1.147 | 51.5 / 29.7 |
| 402 × 874 | 16 Pro, 17, 17 Pro | Dynamic Island | 375 × 815 | 1.072 | 57.8 / 31.7 |
| 440 × 956 | 16 Pro Max, 17 Pro Max | Dynamic Island | 375 × 815 | 1.173 | 52.8 / 29.0 |
| 420 × 912 | Air | Dynamic Island | 375 × 814 | 1.120 | 60.7 / 30.4 |

Every iPhone 12–17 is within −1 / +3 px of the 812 design height at 375 wide. Fitting
the width therefore never crops or letterboxes a 375 × 812 design; a full-height design
gains at most 3 px.

Loads wait until the web view is on screen with a real size. A load that started earlier
(e.g. at cold launch) lay out at WebKit's 980 px desktop default. After every load the
zoom lock is checked and re-applied if needed. If WebKit's page process dies, the page
reloads instead of going blank.

## Push from the web

`../vercel-sim-push` is a web page that pushes links straight into the app. Scan a room's QR code with the Camera (`vercelsim://pair?room=…`) or paste its invite link into the link field, and links pushed to that room open here (or are saved, with a card to open them). Receipts and Live/Away status go back to the page. `Sources/PushHub.swift` holds the client: rooms, the ntfy.sh stream, AES-GCM. `Sources/PushViews.swift` holds the drop-in card and the Options section. It only works while the app is in the foreground; pushes sent while it was away arrive when it comes back. See `../vercel-sim-push/README.md` for the protocol.

## Reliability notes

- **Swipe back / forward** works only within the prototype you opened. It never goes back to
  a blank page or to an earlier prototype, and pages restored by a back swipe are shown at
  once (no held snapshot).
- **Cross-fades** (a link or an iteration inside the page) always finish: on the page's
  ready signal, shortly after it finishes loading, or when the load is cancelled.
- **Links the page can't show** (tel:, mailto:, App Store…) are handed to iOS; vercelsim://
  links inside a page open here.
- **Back from the background:** if iOS ended the page's process, the page that was on
  screen reloads straight away.
- **Interrupted gestures** (a call, Control Center) spring back: the lock-screen swipe, the
  sheet drag, the guide's slides and a saved link's swipe (which never deletes on an
  interruption).
- **Try again** on the error screen retries the link that failed; **Home** remembers the
  page you were on, so swiping up reopens it.

## Launch arguments (testing)

`-url <url>` opens a prototype straight away, `-panel` shows the control panel,
`-iteration <n>` presses iteration *n* after load, and `-pill` shows the on-screen pill
for that launch only.
For example:

```bash
xcrun simctl launch booted com.prototype.vercelsim -url https://product-upscale.vercel.app -pill
```

## Look: Lightweight UI

The app uses noon's **Lightweight UI** kit (github:ayaneshu/lightweight-ui-kit, https://lightweight-ui-kit.vercel.app). Its tokens live in `Sources/Lightweight.swift` (`LW.*`):
- **Look:** the kit's dark theme on all of the app's own screens (Options ▸ Appearance only sets how prototypes are shown), hairline cards with no glass or shadow, and wash fills for pills, tiles and empty states.
- **Type:** Geist (Regular / Medium / SemiBold) for UI text, and Geist Pixel Square for big figures.
- **Controls:** 12 px inputs whose border turns ink on focus; one solid ink primary button per screen; solid danger only for the final delete; every press scales to 97% on the kit's ease-out.
- **Fonts:** `Sources/Resources/Fonts/` holds static TTFs made from the kit's own woff2 files, under the SIL Open Font License (OFL.txt), and they're registered in Info.plist ▸ UIAppFonts.
- **Lock screen:** no clock. It's the paper canvas with a faint dot grid, the Open a prototype card and the Link Directory.
