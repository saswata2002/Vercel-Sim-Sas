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
| Link Directory | The card under *Open a prototype*. Every link you submit (widget or options sheet) is saved automatically once its page loads. Typos, unreachable servers and HTTP error pages (404, 500…) are never saved: newest first, no duplicates, titled from the page once it loads (e.g. *noon — Home*). Tap a row to open it. Swipe left to delete: a short swipe shows Delete, a long one deletes at once. Swipe right to edit: a short swipe shows Edit, a long one opens the editor. There you can rename the link, and change its URL only if you edit it. Your name is never replaced by the page title, and clearing it brings the title back. Press and hold for Edit / Copy Link / Remove. File links (images, PDFs…) are skipped. Long lists scroll inside the card. |
| Lock screen | Your wallpaper, plus the live date and time in the Figma typography (Motion (Sas) 1526:74437). **Swipe up** resumes the open prototype, or the most recent one. With nothing to open, it shows the panel. **Press and hold** opens the panel. |
| Options sheet | **Double-tap anywhere** (over a prototype or on the lock screen) to open a bottom sheet with every option. A two-finger press-and-hold or a shake (Simulator: ⌃⌘Z) also opens it. Contents: the iteration selector (numbers, reset and any other controls such as *Spec Sheet*), the address field, Reload, Screenshot (share sheet), Home, recents, status bar, home indicator, 375 scaling, the on-screen iteration pill, Appearance, device details, and Clear cookies & cache. |
| Iteration selector | The prototype's own picker (1 · 2 · 3 · 4 · reset · Spec Sheet…) is detected and hidden in the page, then shown in the options sheet. Turn on *Iteration pill on screen* for a floating pill. |
| Device fit (automatic) | The app detects the iPhone (model, screen, scale, safe areas) and locks the page's viewport to `width=375` at a fixed scale of screen width ÷ 375, with `user-scalable=no`. The design lays out at exactly 375 CSS px (including `100vw`), keeps its proportions, and fills the screen. The height follows the device's aspect ratio, and safe areas reach the page as `env(safe-area-inset-*)` in its own px. The page's own viewport tag is rewritten, keeping keys like `interactive-widget`. |
| No zoom | Pinch zoom, double-tap zoom and zoom bounce are all off, so the prototype stays fixed to the screen. Double-tap opens the Options sheet instead. |
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

A double-tap also reaches the prototype as two taps. That's harmless on most screens;
use the two-finger hold where a double tap would do something in the prototype.

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

## Launch arguments (testing)

`-url <url>` opens a prototype straight away, `-panel` shows the control panel,
`-iteration <n>` presses iteration *n* after load, and `-pill` shows the on-screen pill
for that launch only.
For example:

```bash
xcrun simctl launch booted com.prototype.vercelsim -url https://product-upscale.vercel.app -pill
```
