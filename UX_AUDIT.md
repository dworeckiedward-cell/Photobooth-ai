# Boothify — UX/UI Audit

Read-only assessment. Reference state: iOS commit `dd016e9` (M0-M7 +
IM0-IM4 + BM0-BM3), web viewer at backend commit `1076c84`
(`src/app/v/[shortCode]/page.tsx`).

Benchmarks: **Loomabub** (direct competitor / operator daily-driver),
**Halide** (single-purpose camera), **Darkroom** (gesture editor),
**Procreate** (touch-first, zero chrome), **Linear** (motion + microcopy),
**Apple Camera / Photos** (HIG baseline).

Scoring: 🔴 1 / 🟠 2 / 🟡 3 / 🟢 4 / ⭐ 5.

---

## Overall score: **🟡 3.1 / 5** — functional, branded, behind world-class on motion + accessibility + state-design

The product is **further along than most pre-launch iOS apps** — there's
a coherent dark theme, the FFmpeg + Apple Sign In + cloud upload pipeline
is solid, recording UX is one-handed-reachable. But polishing details
(Dynamic Type, hardcoded sizes, error states, mode-context coloring, app
chrome on first launch) keep us a tier below Halide/Darkroom.
Loomabub-parity is achievable in 2-3 focused polish sprints; Halide-parity
in 1-2 month follow-ups around motion + onboarding.

---

## Per-screen inventory

| Screen | File | Function | Empty | Loading | Error | Offline |
|--------|------|----------|:-----:|:-------:|:-----:|:-------:|
| Splash | `RootView.AuthSplashView` | Keychain probe | n/a | spinner only | — | — |
| Login | `LoginView` | Apple sign-in | n/a | inline | inline | — |
| Mode select | `ModeSelectionView` | Photo vs 360 entry | n/a | — | — | — |
| Onboarding quiz | `OnboardingQuizSheet` | First-login preferences | n/a | — | — | — |
| Photobooth landing | `PhotoboothLandingView` | Pick / create event | ✓ | spinner | inline | — |
| Event hub (photo) | `EventHubView` | Operator console | ✓ | inline | inline | — |
| Camera (photo) | `CameraScreen` | Capture + countdown | n/a | inline | permission overlay | — |
| Style picker | `StylePickerView` | Pick AI style | grid | inline | — | — |
| Result (photo) | `ResultView` | AI photo + share | n/a | progress card | retry panel | — |
| Gallery | `GalleryView` | Event photos | ✓ | spinner | inline | — |
| Slideshow | `SlideshowView` | TV mode | ✓ | spinner | — | — |
| 360 landing | `Booth360LandingView` | 360 event entry | ✓ | spinner | inline | — |
| 360 hub | `Booth360EventHubView` | 360 operator console | ✓ | inline | inline | — |
| 360 recording | `Booth360RecordingView` | Camera + countdown + REC | n/a | inline | permission overlay | — |
| 360 processing | `Booth360ProcessingView` | FFmpeg render progress | n/a | progress ring | inline | — |
| 360 result | `Booth360ResultView` | Final video + share | n/a | placeholder | upload status bar | partial |
| Settings hub | `SettingsHubView` | Per-event prefs | n/a | — | — | — |
| Settings forms | `SettingsDetailViews` / `MVPViews` | Each section | n/a | — | — | — |
| Twilio onboarding | `TwilioOnboardingSheet` | Connect SMS | n/a | inline | inline | — |
| Cloud status | `CloudStatusPanel` | Pipeline counters | shows zeros | spinner | silent fallback | yes ✓ |
| Web viewer | `/v/[shortCode]/page.tsx` | Guest video page | 404 | SSR | 404 | — |

Touch-target sweep: critical CTAs (REC button, primary CTA, sign-in)
all ≥48pt. Secondary tiles in result/event-hub action grids are 56pt min
height. Only failure: `StatTile` value labels using `.system(size: 10)`
make them legible-but-fragile under Dynamic Type.

One-handed reachability: ✅ for recording / result / event hub. ⚠️ for
settings sub-forms (long `Form` lists; Submit at top of nav bar via
`EditButton` is hard to reach for a left-handed operator with a wet
right hand).

---

## A1. Typography — 🟡 3 / 5

**Hierarchy** is present (largeTitle / title2 / headline / body / caption /
caption2) but **mixed with hardcoded sizes**. Grep finds `.system(size: …)`
in ModeSelectionView, PhotoboothLandingView, EventHubView, Booth360LandingView,
Booth360EventHubView, LoginView, GalleryView, SlideshowView — between 10
and 56pt, off the semantic scale.

- Uses SF Pro (default), no SF Rounded — fine for the dark editorial feel.
- **Dynamic Type: broken on hardcoded sizes**, works on semantic ones.
  An operator with Accessibility large text on will see clipped headlines.
- **Tracking** is set on `GradientHeading` (`kerning: -0.5`) but ad-hoc
  elsewhere. No design token.
- **Tabular numbers:** `Booth360RecordingView.timeString` uses
  `.font(.caption.monospaced())` ✓. `Booth360ProcessingView` "42%"
  counter uses `.font(.system(size: 40, weight: .bold, design: .rounded))`
  — **missing `.monospacedDigit()`**. The percent jitters left/right
  by 1-2pt every tick. Highly visible during render.
- **Consistency:** Boothify wordmark renders at 4 different sizes /
  weights across Login, ModeSelection (micro-brand), PhotoboothLanding,
  Booth360Landing.

**What world-class does:** Halide uses **exactly 5** type sizes app-wide,
all on the SF semantic scale, all Dynamic-Type-aware. Linear publishes a
typography spec that fits on one screen.

## A2. Color System — 🟡 3 / 5

`BoothifyTheme` covers the foundation cleanly: `bg`, `surface1/2`,
`surfaceLine`, `textPrimary/Secondary/Tertiary/Muted`, plus brand colors
(`violet`, `fuchsia`, `emerald`, `amber`, `pink`). `primaryGradient` and
`headingGradient` are reusable.

But there's NO **semantic `error`/`warning`/`success`** token, so:
- `.red.opacity(0.85)` is hardcoded in **PhotoboothLandingView**, **EventHubView**,
  **Booth360LandingView**, **GalleryView**, **TwilioOnboardingSheet**, **ResultView**,
  **AccountSettings** (Delete section).
- `BoothifyTheme.emerald` IS used semantically for success markers (e.g.
  cloud status "done" tile, M2 Sign-in confirmation circle), but inconsistently.
- `BoothifyTheme.amber` doubles as both "warning" and "360 mode accent" —
  ambiguous semantic.

**Dark mode:** project ships dark-only (`UIUserInterfaceStyle = Dark` in
pbxproj). This is fine for the operator's event environment, but means
**no light mode at all** — sensible decision given the use case but worth
documenting as intentional.

**Contrast (WCAG AA, 4.5:1):**
- `textPrimary` (white) on `bg` (zinc-950): ratio ≈ 19:1 ✓
- `textSecondary` (zinc-400) on `bg`: ≈ 7:1 ✓
- `textTertiary` (zinc-500) on `bg`: ≈ 5:1 ✓ (just over)
- `textMuted` (zinc-600) on `bg`: ≈ 3:1 ❌ (below AA for body) — used for
  faint footers, OK at large size, **NOT** for any actionable copy.
- `violet` on `surface1` (e.g. "Send again" pill in `uploadStatusBar`):
  ≈ 4.6:1 ✓ but borderline.

**Branding conflict:** when an event has both an operator-uploaded logo
(M7 `BrandOverlayLayer`) AND the Boothify wordmark on the share page,
there's no spec for which wins. Currently both render — visually muddy on
the web viewer.

## A3. Spacing & Layout — 🟡 3 / 5

A **4/8/12/16/20/24/32/48** scale is implicit in the code (the violet
gradient + 16pt radius repeat constantly) but **never declared**. Off-scale
spacings appear: `.padding(13)`, `.padding(18)`, `.padding(20)`,
`.padding(24)` instead of `padding(16)` or `padding(24)`. None catastrophic,
but you can feel a quarter-pixel rhythm break under a designer's eye.

- **Safe areas:** `Photobooth_aiApp` sets `.ignoresSafeArea()` correctly
  on full-bleed views (recording, slideshow). Dynamic Island clear on
  ModeSelection (`microBrand` shoves wordmark to x≈130).
- **Landscape:** `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`
  allows all orientations; iPhone allows landscape + both portraits.
  **Most ScrollViews don't lay out well in landscape** — `EventHubView`'s
  `frame(maxWidth: 720)` is centered with no horizontal column → wasted
  space on iPad landscape. Looks like a phone-app stretched.
- **Cramping risk:** `Booth360ResultView` 6-tile action grid (Share /
  QR / SMS / Copy / Save / New) gets tight at iPhone SE (4.0" 320pt
  width) — each tile is ~48pt wide. Adequate but loses visual breathing
  room.
- **Empty spaces:** `Booth360ProcessingView` has lots of dead space
  around the 160pt progress ring. World-class would fill it with
  process-storytelling (a thumbnail montaging in real time, sample
  output mock). Today: just amber gradient + step list.

## A4. Iconography — 🟢 4 / 5

100% SF Symbols (no custom). Stroke weights default to `.regular`/
`.semibold` — feels coherent. Semantic choices are mostly right:
`camera.aperture`, `gearshape.fill`, `square.and.arrow.up`, `qrcode`,
`video.fill`, `slowmo`. A few oddities:
- `arrow.down.to.line` for "Save" — fine but `square.and.arrow.down` is
  the iOS convention for "save to Photos". Mild HIG drift.
- `phone.bubble.fill` for WhatsApp — meh; we have the custom WhatsApp
  glyph in `ResultView` (`WhatsAppIcon` private SVG) but use SF on the
  360 result. Mixed.
- `airplayaudio` for "AirDrop" tile in photo flow — wrong icon
  conceptually. Should be `square.and.arrow.up` (same icon as Share —
  but text differentiates).

Touch targets around icons: 44-56pt achieved via card containers, never
bare icons-as-buttons.

## A5. Motion & Transitions — 🟠 2 / 5

The single weakest dimension.

- **NavigationStack push/pop** uses default slide transitions — fine.
- **`.spring()`** is used in: photo result reveal animation, copy-link
  flash, onboarding step dots, segment dragging in `CaptureTimelineEditor`,
  segment selection in `StylePickerView`. Half-baked but right idea.
- **Linear / ease curves** dominate elsewhere with bare `.animation(.easeOut)`
  on opacity flips — fine but flavorless.
- **Durations:** mostly 0.12-0.4s (good). Onboarding step dot animation
  uses `.spring(response: 0.35, dampingFraction: 0.85)` — tasteful.
  Result reveal uses `.easeOut(duration: 0.7)` — slow, feels heavy.
- **No motion design system.** Every view picks its own curves. World-class
  apps publish a `Motion.swift` with 3-4 named springs (`subtle`,
  `bouncy`, `snappy`, `gentle`) and 2-3 durations.
- **`Reduce Motion` is NOT honored anywhere.** No `@Environment(\.accessibilityReduceMotion)`
  checks. The Result screen reveal and the cosmic StarField animation
  ignore the user's accessibility setting — **an accessibility regression**
  from Apple HIG.
- **Microinteractions:** present (button press scale, copy-confirm
  checkmark, success haptic) but inconsistent. The "Send again" pill
  doesn't animate state change. The QR sheet pops without entry animation.

## A6. Haptics — 🟢 4 / 5

`Haptics.tap()`, `.notify()`, `.selection()` enum in `Theme.swift` is good
infra. Used at the right moments:
- ✓ `tap(.medium)` on countdown start, REC button
- ✓ `notify(.success)` on capture, render-complete, copy-link
- ✓ `notify(.error)` on Twilio failure, save failure
- ✓ `selection()` on flip-camera, style picker
- ✓ `tap()` on minor navigation

A few **missed opportunities**:
- Style selection in `StylePickerView` — currently silent. Should `.selection()`.
- Onboarding quiz "Next" tap — silent. Should `.tap(.light)`.
- "Send again" pill in upload status bar — fires `.tap()` ✓ but no
  follow-up `.notify(.success)` when the retry succeeds (Booth360CloudUploader
  doesn't haptic on resolve).
- App launch — Apple Camera fires a subtle `.light` haptic on viewfinder
  ready. We don't.

Overall not **overdone** — operator hands won't get fatigued. Good.

## A7. Sound Design — 🟡 3 / 5

- `Booth360RecordingView` plays system sounds (`AudioServicesPlaySystemSound`)
  for countdown ticks (`SoundID 1306`), record start (`1057`), record end
  (`1106`). Diegetic, recognizable — feels right.
- Photo flow has **no sound** — silent capture. Apple Camera always emits
  a shutter snap (legally in some jurisdictions). We don't — possibly
  intentional for kiosk privacy, possibly an oversight.
- **`AVAudioSession.Category.playback` not configured.** System sounds
  respect the silent switch by default — so during a wedding ceremony in
  silent mode, the operator gets no audio countdown. **Likely the right
  call** but undocumented.
- No success "ding" on render complete (Halide has one).
- Result preview video plays with audio **un-muted** (`Booth360ResultView`
  `VideoPreviewPlayer.setup()`). If the operator opens result quickly
  after a recording, audio surprises them. Subtle issue.

## A8. States — Empty / Loading / Error / Offline — 🟡 3 / 5

**Empty states:**
- ✓ `Booth360LandingView` has a proper empty card with icon + copy.
- ✓ `GalleryView` empty has icon + text but **no CTA** ("No photos yet").
  Should suggest tapping back / starting capture.
- ✓ `EventHubView`'s recent-captures block goes empty gracefully.
- ⚠️ `PhotoboothLandingView` with zero events shows the create card but
  no "you'll see your events here" sub-line.
- ⚠️ `CloudStatusPanel` shows four "0" tiles in a fresh event — looks like
  loading state, no copy distinguishing "empty" from "loading".

**Loading states:**
- Spinners ubiquitous (`ProgressView`) but flat.
- **No skeleton loaders / shimmer** anywhere. World-class apps replace
  spinners with grayed placeholder shapes that match the eventual layout
  (`Booth360EventHubView` recordings grid would be a perfect candidate).
- Loading copy: present in `Booth360ProcessingView` step list ("Stabilizing
  video", "Adding soundtrack and overlays") — nicely on-brand. Missing
  elsewhere (PhotoboothLanding fetch shows bare `ProgressView`).

**Error states:**
- Mostly **inline red text below the trigger** (`Booth360LandingView`
  error, Twilio onboarding error, AccountSettings delete error). Adequate
  but **not actionable** — usually shows the raw `error.localizedDescription`.
- ✓ `ResultView` photo "Generation failed" panel is the gold standard
  here — illustrated icon, friendly copy, two buttons ("Try another style"
  / "New photo"). Should be the template for all errors.
- ✓ `Booth360RecordingView` permission overlay is good — illustrated,
  copy explains what's needed, "Open Settings" CTA.

**Offline:**
- `CloudStatusPanel` degrades to local snapshot — invisible to operator
  ✓ but no "offline" indicator anywhere in the UI.
- Recording works offline (FFmpeg local) — operator unaware they're offline
  until upload fails on `uploadStatusBar`.
- **No proactive offline banner.** A "📶 Working offline — uploads will
  resume" pill at the top of the event hub would be Loomabub-grade
  professionalism.

## A9. Onboarding & First Run — 🟢 4 / 5

- **First-run quiz** (`OnboardingQuizSheet`, IM3) is **above average**:
  4 skippable steps, progress dots, applies real defaults to first event
  (`AppState.createEvent` reads `OnboardingStore.lastAnswers`). Linear-grade.
- **LoginView** is functional but **doesn't sell**: a camera-aperture
  glyph + "Boothify" + one-line subtitle + Sign-in button. Compare to
  Procreate's animated app icon + tagline + sample brushstroke preview.
- **No "First Event Tour":** an operator who completes the quiz and lands
  on `PhotoboothLandingView` sees an empty list with a text field — no
  "Tap here to create your first event" coachmark. Drop-off risk.
- **No empty-state CTA** beyond the create form (covered in A8).

## A10. Microcopy & Voice — 🟡 3 / 5

- **Language: English only**, no localization. Polish operator (Patryk)
  reads `"Tap to start a 6s recording"` — works (he's bilingual technical)
  but for non-English operators this kills.
  - **No `Localizable.strings` / `String Catalogs`.** Every string hardcoded.
  - `STRING_CATALOG_GENERATE_SYMBOLS = YES` is in pbxproj but no `.xcstrings`
    file exists.
- **Voice:** mostly professional + clear (`"Connect Twilio"`, `"Send by
  Email"`, `"Open Settings"`). Some flavor moments:
  - "Working some magic" (photo loading) — too cute, feels off-brand for
    an event-pro tool.
  - "Mixing pixels with stardust…" / "Asking the AI nicely…" loading
    messages — same issue. Halide would never.
  - "Fahhh sound" (M2 commit message reference) — code-internal but the
    style leaks.
- **Operator vs guest copy mixed:** "Your AI photo is ready" — phrased
  for the guest, but operator sees it on the result screen too.
- **CTA clarity:** mostly OK. "Open demo" (360 tile) → after IM*+BM*
  it's not a demo anymore — copy stale.
- **Error copy:** raw `error.localizedDescription` leaks technical
  language to operators. Should be wrapped (template) in a friendlier
  shell.

## A11. Operator-Context Fitness (UNIQUE) — 🟢 4 / 5

This is where the project's specific care SHOWS. Strongest dimension.

- ✅ **Glanceability:** REC button is 92pt with progress ring. Countdown
  numerals are 220pt. Operator at arm's length can see status in 0.5s.
- ✅ **One-handed reachability:** REC + music + presets row is in the
  bottom 1/3 of the recording screen. Result screen actions are pinned
  to the bottom (BM4).
- ✅ **Thumb zone:** primary CTA in dolnej 1/3 across recording, result,
  event hub. Back chevron is top-left (default iOS, can't fight).
- ⚠️ **Fast-restart resilience:** auth session restores via Keychain ✓
  (M2). **But:** after crash mid-event, the app lands on `ModeSelectionView`
  → operator has to drill back through PhotoboothLanding → event → camera.
  3-tap drill on a queue of guests. Should restore the last-active
  recording route from `UserDefaults`.
- ⚠️ **Glove/wet hand:** REC button is huge (excellent), but small UI
  elements (timeline editor `Slider`, music picker `fileImporter` confirm)
  fight wet fingertips. Acceptable for non-event surfaces.
- ❌ **Battery / thermal indicators:** zero. AVFoundation `ThermalState`
  is queryable; we never show "📛 Device is overheating — pause to cool?"
  pill. After 4 hours of recording 1080p on iPhone 12, thermal throttling
  is real.
- ❌ **Outdoor visibility:** no high-contrast mode hook. Operator in
  bright sun struggles with `textTertiary` zinc-500 on black. iOS has
  `accessibilityDifferentiateWithoutColor` and `accessibilityIncreaseContrast`
  environment values — we honor neither.

## A12. Accessibility — 🟠 2 / 5

The weakest dimension after Motion.

- **VoiceOver labels:** mixed. Critical buttons mostly labeled
  (`accessibilityLabel("Take photo")`, `"Flip camera"`, `"Refresh cloud
  status"`). But:
  - `Booth360EventHubView` job thumbnails — unlabeled.
  - `Booth360ResultView` action tiles — system-labeled via `Label(...)` ✓.
  - `SlideshowView` counter pill — unlabeled.
  - `CaptureTimelineEditor` sliders — system labels OK.
- **Dynamic Type:** broken on every `.system(size:)` (most landing
  pages, login, mode selection, gallery, slideshow). Apple's
  Accessibility Inspector would flag dozens of issues.
- **Reduce Motion:** never checked. StarField, result reveal, onboarding
  spring animations all play full-bore.
- **Reduce Transparency / Increase Contrast:** never checked. Lots of
  `.ultraThinMaterial` backgrounds + `Color.white.opacity(0.05)` surfaces
  that disappear under high-contrast mode.
- **Bold Text setting:** ignored by hardcoded `.system(size:weight:)`.
- **Hit testing on tiny taps:** segment delete in `CaptureTimelineEditor`
  uses the system swipe-to-delete from EditButton — operator-friendly.

## A13. Loomabub Comparison — 🟡 3 / 5

From call transcript + general knowledge of the product:

**Recording screen**
- **Loomabub has:** software stabilization (we have native AVFoundation,
  M1 ✓), per-take preset chips inline below REC, music picker top-right.
- **We have:** preset sheet (M4 quick presets) requires a tap to open,
  music picker is a button + system file picker. Loomabub: fewer taps.
- **Action:** consider inline preset chips (1-tap swap between Quick /
  Standard / Epic) above REC instead of behind a sheet.

**Capture Settings (timeline)**
- **Loomabub has:** drag-handle timeline with visual speed waveform.
- **We have:** `CaptureTimelineEditor` with per-segment sliders, no
  visual representation of the curve.
- **Action:** add a horizontal speed-curve preview strip (Procreate-style
  brush-curve editor) above the segment list.

**Result / Sharing**
- **Loomabub has:** AirDrop, QR, link copy, SMS (we have all 4 ✓ via IM1).
  But Loomabub has a single "Share" button that opens a custom sheet with
  all options in one place.
- **We have:** 6-tile grid (Share / QR / SMS / Copy / Save / New) on a
  small screen — feels cluttered next to Loomabub's one big "Share".
- **Action:** keep all 6 actions but consider primary "Share" button
  + secondary row (QR / SMS / Copy) below.

**Cloud event mirror**
- **Loomabub has:** real-time gallery on the web at a public link.
- **We have:** album mode on `/v/[shortCode]/album` (BM3) ✓ — parity
  achieved. Minor: ours doesn't auto-refresh; Loomabub's polls.

**Onboarding**
- **Loomabub:** account → first event in <30s, no quiz.
- **We:** Apple Sign In → onboarding quiz (4 steps) → mode select →
  PhotoboothLanding → create event → enter event. 5+ taps. Quiz is
  skippable but its presence on first launch reads as "more setup".

## A14. Guest Viewer (web `/v/[shortCode]`) — 🟢 4 / 5

Surprisingly good for an MVP. **Probably the strongest single screen
in the product** for first-impression value.

- ✅ **Fast SSR**, signed URL fetched server-side, page renders 200ms.
- ✅ **Mobile-first 9:16 aspect ratio** with sm:aspect-video escape hatch.
- ✅ **Autoplay + muted-eligible + playsInline + loop** — mobile-correct.
- ✅ **OG metadata** (`generateMetadata`) for SMS unfurl. Title is
  `"<EventName> — 360 video"`. Good.
- ✅ `robots: noindex` — privacy correct for private mode.
- ✅ Branded header with event logo (when uploaded).
- ✅ Album mode renders auto-grid with "NOW" badge on the current take.
- ⚠️ **No share affordance for the guest** to forward to a friend (the
  `Share` button is just a link, not a native share intent — `navigator.share()`
  API would unlock OS-level share sheet on mobile).
- ⚠️ **No CTA for the operator** — page doesn't end with "Want this at your
  event? Boothify.app". **Massive missed marketing surface.** A subtle
  footer link could compound viral growth.
- ⚠️ Loading state: nothing. If the signed URL is slow, the user sees
  a black `<video>` element. Skeleton loader / poster image would help.
- ⚠️ **No download progress** — Download link triggers immediate browser
  download with no indicator.
- ⚠️ Album mode lazy-loads ALL videos as `<video>` elements — on a 50-take
  event that's 50 simultaneous network requests. Should `preload="none"`
  or use poster frames.

---

## TOP 10 ISSUES — Impact × Effort

Ranked: high-impact-low-effort first. Severity vs effort matters.

| # | Issue | Severity | Where | Effort | Affects |
|---|-------|----------|-------|--------|---------|
| 1 | `.system(size: 40)` percent counter jitters during render | 🟠 high | `Booth360ProcessingView:111` | XS | Operator: watches it for 10s every recording |
| 2 | `.red.opacity(0.85)` hardcoded across 6 files — no `Theme.error` token | 🟡 med | Theme.swift + 6 callsites | XS | Maintainability + dark-mode contrast |
| 3 | `Reduce Motion` ignored everywhere (StarField, reveal anim, springs) | 🟠 high | Theme + all view files | S | A11y regression; App Review risk |
| 4 | Hardcoded `.system(size: N)` blocks Dynamic Type on 7 screens | 🟠 high | Login, ModeSelection, EventHub, Booth360EventHub, Photobooth/360 landings, Gallery, Slideshow | S | Accessibility, App Review |
| 5 | No "offline" indicator — operator unaware until upload fails | 🟠 high | (new) banner in event hubs | M | Event survival; trust |
| 6 | No thermal state hook — long sessions throttle silently | 🟠 high | `CameraController` + ProcessingView | M | Event survival; iPhone 12/13 |
| 7 | Crash-restart drops operator on ModeSelection — 3-tap drill back | 🟡 med | AppState + RootView | M | Event survival |
| 8 | `Booth360ResultView.VideoPreviewPlayer` autoplay with sound | 🟡 med | Booth360ResultView | XS | Surprise audio during quiet event moments |
| 9 | Web viewer: no `navigator.share()`, no Boothify CTA footer | 🟡 med | `/v/[shortCode]/page.tsx` | S | Viral growth surface; one screen our guest sees |
| 10 | "Working some magic" microcopy off-brand for pro tool | 🟡 med | ResultView | XS | Brand consistency |

**Quick-win candidates from this list:** 1, 2, 4 (partial), 8, 10.
**Medium effort that pay off big:** 5, 6, 9.

---

## World-Class Gap Analysis

### Halide (camera app benchmark)
Halide is the gold standard for single-purpose iOS camera apps. Their
playbook:
- **Touch-anywhere reachability** for every critical action; nothing in
  the top half during capture.
- **Tasteful, contextual sound + haptic** on every capture (snap + medium
  impact).
- **Zero chrome** while composing — settings drawer is gesture-summoned,
  not button-tapped.
- **One typography spec** the entire app inherits.

**What to adopt:** publish a `Motion.swift` + `Typography.swift` spec
file. Move recording-screen settings/music behind a swipe-up gesture
(Procreate-style) so the main view is camera + REC + nothing else.

### Darkroom (gesture-driven editor)
Darkroom feels like a hardware tool because **every editor surface uses
gesture, not buttons**. Sliders snap to defaults at midpoint. Long-press
reveals before/after.

**What to adopt:** `CaptureTimelineEditor` should support **drag the
segment edge in the live timeline** (Darkroom-style) instead of separate
duration slider + speed slider. Long-press a segment to A/B preview.

### Procreate (touch-first, zero chrome)
Procreate hides ALL chrome the moment you start drawing. Returns on tap.
Every gesture is discoverable but never imposed.

**What to adopt:** during recording, hide everything except REC + timer.
Tap once anywhere outside REC to reveal music/presets/back. Auto-hide
again after 2s of no interaction. Matches what the operator actually
needs in their hands during a take.

### Linear (motion + microcopy)
Linear's secret is **purposeful motion + clinical microcopy**. Every
transition has a reason (slide in = new context, fade = same context
new state). Every error message is empathetic AND actionable.

**What to adopt:** a one-page motion spec (3 springs named `subtle`,
`bouncy`, `snappy` + 2 durations `quick`, `gentle`). One-page microcopy
guide ("operator voice: confident, brief, never cute"). Replace
"Working some magic" with "Generating photo — about 10 seconds".

### Stripe Dashboard (data density)
Stripe makes 1000 metrics readable at a glance. Type hierarchy + table
zebra-stripe + monospaced numerals do all the work.

**What to adopt:** `CloudStatusPanel` counters should use
`.font(.title3.monospacedDigit())` so a `12 → 13` flip doesn't shift
neighboring tiles. Photo gallery thumbnails should be **fixed grid**
with a count badge per cell (style chip overlay), not bare squares.

### Apple Camera / Photos (HIG baseline)
Hardware shutter button on Camera works in any orientation. Photos uses
the system share sheet for everything — no in-app SMS / WhatsApp / Email
buttons. Both are minimal.

**What to adopt:** for photo flow, replace SMS / WhatsApp / Email
individual tiles with a single big native `ShareLink` (already done for
360 ✓). Frees pixels for the photo itself. Operators who specifically
need Twilio SMS keep the dedicated SMSSheet behind one of the 3
remaining tiles.

---

## Closing observations

- The product has a **clear visual identity** (dark violet/fuchsia kiosk
  aesthetic) — that's an asset, don't dilute it.
- The biggest **felt-quality gap** is **state design + motion + accessibility**
  — three dimensions that aren't user-requested but make the difference
  between "this works" and "this is built by pros".
- The biggest **business risk in UX** is the **operator drill-back after
  a crash** (issue #7). Patryk will lose a guest, blame the app, and
  it'll be hard to un-blame.
- The biggest **upside** is the **web viewer footer CTA** (issue #9) —
  every share = potential lead.
