# Strategic Proposals — UX/UI uplift toward world-class

Read `UX_AUDIT.md` first. The audit identified ~14 dimensions to
improve; this document selects **4 strategic moves** that, taken
together, lift the felt quality past Loomabub parity and meaningfully
toward Halide / Linear / Procreate.

Each proposal includes the problem, the spec (technical + visual), an
inspiration anchor, effort estimate, risk, and a recommended sequence.

**None of these are implemented in this run.** They're framed so that
"yes" → implementation is mechanical, "no" → no work lost.

---

## P1 — Motion + Typography spec, app-wide

**Hook:** *One file, three named springs, one type scale — the moment
Boothify stops feeling like seven views written by seven people.*

### Problem
Audit A1, A5 (typography + motion).
- 7+ hardcoded `.system(size: N)` callsites with no shared scale.
  `Booth360RecordingView` uses size 220 for countdown, `LoginView` uses
  56 for icon, `EventHubView` uses 26 for headline, `CloudStatusPanel`
  uses 10 for label.
- Every animation picks its own curve. `.easeOut(0.7)` here,
  `.spring(response: 0.35, dampingFraction: 0.85)` there, default
  `.animation()` elsewhere.
- Reduce Motion ignored everywhere except where QW3 just patched it.

### Spec
Two new files:

`Photobooth-ai/DesignSystem/Typography.swift` — typed helpers backed by
SF Pro semantic scale, all Dynamic-Type-aware:

```swift
enum BoothifyType {
    static let display      = Font.system(.largeTitle, weight: .bold)
        .leading(.tight)               // event names, mode tile headlines
    static let title        = Font.system(.title2,     weight: .bold)
    static let body         = Font.system(.body,       weight: .regular)
    static let bodyEmphasis = Font.system(.body,       weight: .semibold)
    static let caption      = Font.system(.caption,    weight: .medium)
    static let monoNumber   = Font.system(.body,       weight: .semibold)
        .monospacedDigit()             // counters, timers, %
    // Special-purpose, single-callsite holdouts:
    static let countdown    = Font.system(size: 220, weight: .heavy, design: .rounded)
        .monospacedDigit()             // the 3-2-1 in recording
}
```

`Photobooth-ai/DesignSystem/Motion.swift`:

```swift
enum BoothifyMotion {
    /// Default for tap feedback, sheet appearance, state toggles.
    static let snappy   = Animation.spring(response: 0.28, dampingFraction: 0.85)
    /// Slight bounce — for confirmation flashes (copy-link, success).
    static let bouncy   = Animation.spring(response: 0.35, dampingFraction: 0.72)
    /// Subtle hand-feel — for drag handles, slider returns.
    static let gentle   = Animation.spring(response: 0.45, dampingFraction: 0.92)
    /// Linear timing for progress bars + ring fills.
    static let progress = Animation.easeInOut(duration: 0.4)

    /// Reduce-Motion-aware wrapper. Call instead of withAnimation
    /// directly. When the user has Reduce Motion ON, runs body without
    /// animation.
    @MainActor
    static func animate(
        _ animation: Animation,
        reduceMotion: Bool,
        _ body: () -> Void
    ) {
        if reduceMotion {
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx, body)
        } else {
            withAnimation(animation, body)
        }
    }
}
```

Sweep: replace every hardcoded `.system(size:)` with `BoothifyType.*`
and every inline `.spring(…)` / `.easeOut(…)` with
`BoothifyMotion.{snappy,bouncy,gentle,progress}`.

### Inspiration
Halide ships exactly 5 type sizes app-wide. Linear publishes a one-page
motion + typography spec. The discipline is more important than the
specific numbers.

### Effort
**3-4 days.** ~30 files touched; mostly mechanical search-and-replace
with manual review for sizing context. Per-file change is trivial; the
risk is missing a callsite or breaking a layout that relied on a
specific px count.

### Risk
**Low-Medium.** Mechanical. Visual diff per screen is mandatory before
merge — some layouts may need 1pt nudges as semantic fonts size
slightly differently than hardcoded ones.

### Sequence
**Before the next polish prompt.** Every future view inherits the
system; without it we'll keep auditing the same drift.

---

## P2 — Operator HUD: persistent status overlay during event

**Hook:** *Battery + thermal + network + queue status, always visible
in one 28pt-tall strip. Built for the operator who's three guests deep
and can't drop the iPad to check Control Center.*

### Problem
Audit A11 (operator-context fitness), TOP 10 #5 + #6.
- No proactive indicator when the iPad goes offline. Operator records 5
  takes before realizing none uploaded.
- No thermal indication. After 4 hours of 1080p recording, iPhone 12/13
  starts throttling — operator sees mysterious slow renders without
  knowing why.
- No queue indicator. If `Booth360UploadQueue` has 3 pending failed
  uploads, only the operator who navigates to those specific result
  screens knows.

### Spec
New top-of-screen overlay component, visible on `EventHubView`,
`Booth360EventHubView`, `Booth360RecordingView`, `CameraScreen` —
basically every screen during an active event.

Layout: a 28pt-tall full-width pill below the safe area, sliding in
from top when ANY indicator is non-nominal:

```
┌──────────────────────────────────────────────┐
│ 🟡 Offline · Uploads paused      📶 3 queued │
└──────────────────────────────────────────────┘
```

States:
- **🟢 All good** — overlay hidden (no chrome when no problem).
- **📶 No network** — yellow banner, "Offline — uploads will resume".
- **🔥 Thermal `.serious` / `.critical`** — orange, "Device is
  warming up — consider a brief pause". (`ProcessInfo.processInfo.thermalState`.)
- **🔋 Battery <15%** — red, "Battery low — plug in".
- **☁️ Queue >0** — neutral, "N uploads pending" (auto-clears when
  queue empties).

Multiple states stack inline left-to-right separated by `·`.

Pulled together in a new `OperatorStatusOverlay` view, mounted in
`RootView`'s navigation stack root via `.overlay(alignment: .top)` so
it's always above the chrome. Listens to:
- `NWPathMonitor` (Network framework) for connectivity
- `ProcessInfo.thermalStateDidChangeNotification` for thermal
- `UIDevice.batteryLevelDidChangeNotification` (after enabling
  `isBatteryMonitoringEnabled`)
- `Booth360UploadQueue.shared.pendingCount` observed via @Observable

### Inspiration
Apple Maps shows "Searching for GPS" pill during weak signal. Stripe
Dashboard's status bar surfaces only what's broken. Linear's "Connection
lost" toast.

### Effort
**1.5-2 days.** New view + 4 OS-level observers + plumb into RootView +
debounce logic (don't flicker when network blinks for 200ms).

### Risk
**Low.** No core flow touched. Worst case: overlay shows when it
shouldn't (visual annoyance, easily silenced).

### Sequence
**Before the first real event.** This is the single change that
upgrades event-day reliability without any backend work.

---

## P3 — Result screen redesign: gesture-driven, Darkroom-style

**Hook:** *Big preview. Swipe up for sharing. Long-press for QR.
Double-tap for save. Zero button grid.*

### Problem
Audit A11 (operator-context fitness) + Loomabub comparison (A13).
- `Booth360ResultView` action grid is 6 tiles (Share / QR / SMS / Copy
  / Save / New) jammed below the preview. On iPhone SE each tile is
  ~48pt — adequate but visually cluttered.
- Operator with wet hands aims at a 48pt tile and may hit "New" instead
  of "Share". High-stakes miss.
- The video preview itself gets <60% of screen height because of all
  the chrome below.

### Spec
Reorganize `Booth360ResultView` (and analogously `ResultView` for
photo) around the preview as the hero:

```
┌─────────────────────────────────┐
│ ←                          ⚙   │   ← back + settings, 44pt corners
│                                 │
│                                 │
│   [VIDEO PREVIEW, full bleed,   │
│    9:16, 75% of screen height]  │
│                                 │
│  ☁️ Uploaded · 9.5s · 1080p     │  ← single-line metadata strip
│                                 │
│  ┌─────────┐  ┌──────────────┐  │
│  │  Share  │  │  New take    │  │   ← two big 64pt buttons
│  └─────────┘  └──────────────┘  │
└─────────────────────────────────┘

Gestures on the video:
  ↑ swipe up    → opens secondary share sheet
                  (QR / SMS / Copy / Save in a single bottom sheet)
  ⌘ long-press  → shows QR fullscreen, release dismisses
  ⌘⌘ double-tap → save to Photos (with haptic confirm)
```

The two big primary buttons handle the 95% case. Power actions (QR,
SMS, Copy, Save) move to gestures + a "More" disclosure for
discoverability.

First-time discoverability: a 1-line hint below the preview on the
first 3 results (UserDefaults counter): *"Tip: swipe up on the video
for more share options."*

### Inspiration
Darkroom's gallery / edit interaction — every secondary action is a
gesture, never a button. Apple Photos uses double-tap zoom + drag-down
to dismiss. Procreate hides chrome the moment you start drawing.

### Effort
**3 days.** New layout + 3 gestures + bottom-sheet "More" component +
first-run tip + verifying both photo and 360 paths.

### Risk
**Medium.** Gestures need conflict resolution with the system video
player's own controls. Wrong gesture sensitivity = power-user weapon
+ beginner frustration. Mitigation: ship behind a setting toggle
("Gesture mode") and A/B with Patryk for one event.

### Sequence
**After the first event with current UI.** Need real-event feedback
on whether the 6-tile grid is actually a problem in practice or just an
audit finding. If event survival is fine as-is, this is polish, not
necessity.

---

## P4 — Guest viewer redesign: turn shares into a marketing surface

**Hook:** *The web page our guests land on is the only Boothify
experience our customers' customers see. Today it's functional. Tomorrow
it's a 6-second pitch for "the next event needs this".*

### Problem
Audit A14 (guest viewer), TOP 10 #9.
- Current `/v/[shortCode]/page.tsx` is competent (autoplay, responsive,
  OG meta) but undersells.
- No native share intent — the "Share" button is just an `<a>` link.
  Mobile browsers expose `navigator.share()` for one-tap OS share sheet.
- No CTA for the operator. A guest who loved the take has no path to
  "Where can I book this for my event?". Compound viral loss.
- Album mode lazily loads every `<video>` as DOM — on a 50-take event
  that's 50 simultaneous network requests. Should use poster frames.
- No loading state — slow signed URL = black `<video>` placeholder for
  3-5s.

### Spec
Two-part rewrite, both in `ai-photobooth/src/app/v/[shortCode]/page.tsx`:

**Part A — Guest experience polish:**
- Replace `<a download>` and the `<a href>` Share with a small client
  component that uses `navigator.share({ url, title })` and falls back
  to copy-link.
- Add a poster frame: server-side extract first frame as JPEG to a
  separate bucket on render (backend addition); use as `<video poster=…>`.
- In album mode, lazy-load videos as poster-only + `preload="none"`;
  swap to `<video>` on tap. 50 takes load instantly instead of saturating
  the network.
- Skeleton loader (Tailwind `animate-pulse` rectangle) instead of black
  video element during signed-URL fetch.

**Part B — Marketing footer (new):**
At the bottom of every viewer page:

```
┌─────────────────────────────────┐
│                                 │
│         Want this at your       │
│         next event?             │
│                                 │
│   ┌──────────────────────────┐  │
│   │   Learn about Boothify   │  │
│   └──────────────────────────┘  │
│                                 │
│   Boothify · AI Photobooth      │
│   for events · since 2026       │
└─────────────────────────────────┘
```

- Subtle, never aggressive (matches the dark editorial vibe).
- Hide it when the host event has `share_mode = private` AND a
  branding_logo_url uploaded (= white-label client paying for clean
  delivery).
- Link goes to a future `/marketing` landing page (separate scope) —
  for now → `https://boothify.app` or similar.

### Inspiration
Linear's signed-out pages have the cleanest "sign-in / try it" footer
in the SaaS world. Notion's public docs subtle "Made with Notion"
attribution. Cameo / Loom's share-page CTA → free signup.

### Effort
**2-3 days.** Part A: 1 day (client component for `navigator.share`,
lazy video, skeleton). Part B: 0.5 day (footer component + white-label
hide logic). Poster frames need a backend extraction step (~1 day) —
optional, could ship Part A + Part B without posters first.

### Risk
**Low.** Web-only. No iOS changes. White-label hide logic protects
against client friction.

### Sequence
**After the first event** to ensure the share-rate signal exists, but
**before any marketing push.** Every link in the wild before this ships
is a missed lead.

---

## What's NOT proposed (and why)

- **Full app onboarding redesign.** IM3's quiz is already above
  average. Better ROI from the marketing footer (P4) than from a
  splashier first-run.
- **Custom navigation transition library.** Apple's default push/pop is
  unimpeachable; adding a custom transition layer is fashionable but
  fragile. P1 (motion spec) covers the in-screen animations that
  actually matter.
- **Color tokens beyond `error/warning/success`.** QW2 covered the
  semantic gap; further color work belongs in a full design system
  pass, not a 1-week project.
- **Localization (i18n).** Strategic but bigger than this scope —
  needs a translator, not a coder.
- **Gesture-driven recording UI** (Procreate hide-chrome-on-record
  pattern). Tempting but risks confusing operators who learned the
  current layout. Park until we have multi-operator usage signal.

---

## Recommended sequence

If Eduardo were to greenlight one at a time:

| # | Proposal | Why first/next |
|---|----------|----------------|
| 1 | **P2 — Operator HUD** | Event-day reliability is the next risk; lowest-effort win that unblocks real-world resilience. |
| 2 | **P1 — Motion + Type spec** | Future-proofs every screen we touch later; mechanical work; pays compound interest. |
| 3 | **P4 — Guest viewer redesign** | Every share = a lead. Cheap, web-only, no iOS regression risk. |
| 4 | **P3 — Result redesign** | Highest UX delta but also highest risk + needs real-event data on whether current grid actually annoys. |

Run them sequentially, not parallel — each touches different layers and
can validate without entanglement.
