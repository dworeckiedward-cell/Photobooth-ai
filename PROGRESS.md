# Boothify 360 — Build Progress (blueprint v4 execution)

Pre-pivot history: git log (this file's previous content = RUN B log),
`docs/PROGRESS.md` (milestone log). This file now tracks the 360-only rebuild,
phase by phase, per Blueprint Section 0.7.

---

## PHASE 0 — Safety net, retarget, foundations — ✅ GATE GREEN

**Changed:**
- Unit-test target `Photobooth-aiTests` added (first tests in the repo).
  Characterization suite (7 tests, all green): EventSettings decode-tolerance
  (incl. the legacy-blob-with-AI-keys guard that must survive the Phase 1 cut),
  APIError.isRetryable mapping, Booth360UploadQueue idempotency/remove,
  Route exhaustiveness (34 cases — compile-breaks on removal, forcing conscious
  updates in Phase 1).
- Shared scheme with TestAction; one-command gate: `scripts/gate.sh`.
- **FFmpeg removed**: default render client switched to the existing
  `Booth360PassthroughRenderClient` at the only concrete call-site
  (`Booth360ProcessingView`), `Booth360FFmpegRenderClient.swift` deleted,
  `ffmpeg-kit-spm` package reference removed from the project. Package.resolved
  clean. Stale FFmpeg comments in ThermalMonitor updated.
- **Retarget: iOS 26.2 → 17.0** (app + tests). Build + tests green at 17.0.
- Sentry DSN: already config-driven (`BOOTHIFY_SENTRY_DSN` Info.plist key,
  no-ops when absent) — consumed as-is, not rebuilt.
- Created: `BACKEND_CONTRACT.md`, `PRIVACY.md`, `DECISIONS_LOG.md`,
  `ASSUMPTIONS.md`, `NEEDS_DEVICE.md`, `OUT_OF_SCOPE_FOUND.md`.

**Gate status:** build green @17.0 · 7/7 tests green · app launches in sim
(test host boots the real app) · ffmpeg-kit gone + unreferenced · render path
works via Passthrough.

**Risks:** deployment target 17.0 verified at compile time only — runtime on a
physical iOS 17 device is NEEDS-DEVICE. Passthrough output = raw recording
(no montage) until Phase 3; this is intentional.

**Deferred to v2:** (none yet)

---

## PHASE 1 — CUT — ✅ GATE GREEN

**Changed:**
- **21 files deleted** (AI/photo surface): StylePicker, InstantLooks + LocalLookProcessor
  + strip/reel composers, green screen (BackgroundReplacer/StudioBackdrop), FaceDetector,
  PhotoUploadQueue, ResultView, Gallery, Slideshow, EventHubView, PhotoboothLanding,
  ModeSelection, CameraScreen (screen; controller extracted), PrintEngine, GIFEncoder,
  BrandOverlayRenderer, OnboardingQuiz, Models.swift.
- **Extractions (before deletions):** `CameraController.swift` (class + delegates +
  preview, KEEP), `DeliverySheets.swift` (ShareSheet — used by 360 hub + settings).
- **Ports:** EventTemplate chips → Booth360LandingView (no-clobber seeding, apply-on-
  create); Start Kiosk Mode → Booth360EventHubView.
- **Repoints:** home tab → Booth360LandingView; kiosk attract → .booth360Recording;
  EventsCalendar + crash-restore → booth360 routes; CloudStatusPanel offline indicator →
  Booth360UploadQueue; app-level network-restore replay → 360 queue.
- **Model (4.E):** EventSettings dropped aiPortraits/effects/stickers/print/
  backgroundRemoval; legacy-blob-with-AI-keys decode test STILL GREEN (no operator
  data loss). APIModels dropped Photo/PhotoList/PhotoStatusQuery/GenerateResult/
  GeminiQuota. BoothifyAPI dropped 11 photo/AI functions.
- **Route enum: 34 → 19 cases**; RootView switch pruned in lockstep; exhaustiveness
  test updated. SettingsHub pruned to 360 reality; share-mode "Album privacy" card cut
  (web photo-album semantics); test-send mechanism removed (returns in Phase 7 on 360
  links); "Default AI Styles" row removed.

**Gate:** build green · 7/7 tests · zero references to cut symbols (grep-verified) ·
launches to 360 entry (Booth360LandingView home tab) · KEEP tests green.

**Risks / carried forward:**
- **Consent gate is NOT wired into the 360 recording path** (it lived in CameraScreen).
  Phase 3 MUST enforce DisclaimerSettings before capture (GDPR, PRIVACY.md).
- `listEventBooth360Jobs(slug:)` exists app-side — verify against backend in Phase 2
  (may shrink GAP #1).
- Session gallery = hub's recent-recordings list; persistent gallery gated on GAP #1.

**Deferred to v2:** none new (test-send rebuild is Phase 7, not v2).

---

## PHASE 2 — Data & backend contract — ✅ GATE GREEN

**Changed:**
- **GAP #1 closed, not built:** the job-listing endpoint already exists
  (`GET /api/events/{slug}/booth360-jobs`) — the audit missed it because it
  lives under /api/events. Wired it: `Booth360Job(dto:…)` hydration init
  (unknown status → .failed + loud errorMessage) + `AppState.hydrateJobs` (local
  wins / insert server-only / backfill share URL) + hub calls it on load. Clip
  history survives reinstall. Graceful no-op offline.
- **StorageLifecycle** (blueprint §8, Decision 6): raw/{jobId}.mov purged
  post-render, masters/{eventId}/ capped (default 50, newest win), low-storage
  responder (raws first, then halve masters), `isStorageLow` fail-safe.
  4 unit tests green. Phase 3 wires purge into the real render path.
- Decode-compat: Phase 0's legacy-blob test already proves post-cut safety
  (ran green through the Phase 1 cut) — nothing extra to build.
- Migrations: nothing to feature-detect app-side (14 = AI-photo slots, likely
  obsolete; 15 = backend-internal auth). Documented in BACKEND_CONTRACT.md.

**Gate:** build green · 11/11 tests · purge policy unit-tested · app tolerant
of absent backend (hydrate/queues catch; demo mode).

---

## PHASE 3 — Render core + non-blocking flow — ✅ GATE GREEN (make-or-break)

**Changed:**
- **RenderSpec** (spec of record: 1080×1920/30/H.264; Fast 8 Mbps / Best 14 Mbps;
  15 s hard cap) + **RenderTimeline** (Phase 3: full-range 1×; Phase 4 swaps the
  builder, not the export path).
- **Booth360RenderEngine** (pure, sim-testable): composition builder (segment
  insert + scaleTimeRange, duration cap, aspect-FILL — crop never stretch) +
  AVAssetReader→AVAssetWriter export (VideoToolbox H.264 + AAC, autoreleasepool
  pumps, cancellation).
- **Booth360NativeRenderClient** = new default behind the protocol: job
  bookkeeping, StorageLifecycle (master placement, ACTUAL raw purged on success
  only, per-event cap), **honest links** (publicShareURL nil until uploader
  confirms — mock links gone), **upload-initiation regression fixed** (deleted
  FFmpeg client was the only enqueue trigger; found by verification).
- **Non-blocking kiosk:** renders owned by `AppState.startRender` (idempotent);
  ProcessingView can't kill an export by navigation; kiosk "Next guest" button
  (localized) returns to attract mid-export.
- **Consent gate wired into the 360 recording path** (GDPR risk from Phase 1
  closed): DisclaimerConsentSheet before camera when required; decline → pop.
- **120 fps capture path**: `configureHighFrameRate` (≥1080p formats, smallest
  format that reaches the rate, honest fallback + Sentry breadcrumb); pure
  `bestFrameRate` policy unit-tested. **Low-storage block** before recording.

**Gate A:** 18/18 green — e2e synthetic→MP4 (duration/dims/fps/codec asserted),
composition assembly, hard cap, timeline math, writer settings per preset,
fps-fallback policy, MainActor-responsive under 3 concurrent renders.

**Gate B → HANDOFF:** real 120/240 capture, real-footage output quality,
consent+kiosk loop on hardware, iOS 17 runtime.

**Note:** e2e size floor calibrated to synthetic content (solid frames compress
below average bitrate); the real 8–15 MB window is Phase 7's file-size test on
realistic footage.

---

## PHASE 4 — Timeline & motion — ✅ GATE GREEN

**Changed:**
- **MotionTemplates**: Hero Slow / Reverse Bounce / Loop Promo emit multi-segment
  `RenderTimeline`s; ramp curves gentle/punchy/dramatic; eased ramps approximated
  by 0.1 s-source sub-segment stepping (documented constant); **interpolation
  clamp** — hero speed floors at outputFPS/captureFPS, `clamped` flag surfaces a
  breadcrumb (never fake smoothness). Loop Promo's intro/outro speeds match for
  clean social loops.
- **Real reverse** (`Booth360ReverseEncoder`): chunked (0.2 s) last→first
  re-encode into an upright intermediate — bounded memory, autoreleasepool per
  chunk, cancellation. Reversed spans are silent (soundtrack lands in Phase 5).
- **Engine**: composition builder handles reversed segments via intermediates on
  the SAME track with time-keyed aspect-fill transforms; audio inserts stay
  aligned (empty ranges under reversed spans).
- **Client**: reads `ai360.motionTemplate`/`rampCurve` (Optional — decode-safe),
  measures real capture fps from the asset, renders through the template.
- **Settings**: "Motion" card (template + ramp feel pickers + honest copy).

**Gate A:** 27/27 — clamp policy, 120fps honest hero, template structures
(single hero plateau, contiguous source tiling, loop-matched ends), ramp step
resolution + monotonicity, curve differentiation, speed→duration through the
real engine, and **reverse frame order verified on real pixels** (hue of first
reversed frames == hue of last input frames).

**Gate B → HANDOFF:** does the motion look PRO on real spinning footage (ramp
feel, motion blur) — L3 calibration.

---

## PHASE 5 — Overlays, intro/outro, audio — ✅ GATE GREEN

**Changed:**
- **OverlaySpec**: size-match validation (exact ok / same-aspect scale+WARN /
  aspect-mismatch REJECT — never stretch) + real-transparency probe (CIAreaMinimum);
  operator-legible messages per verdict.
- **Engine**: CoreAnimationTool doesn't run in reader→writer, so overlays are
  composited PER FRAME on the GPU (CoreImage → pool buffers → adaptor). Fixed a
  real heap-corruption crash: the pixel-buffer adaptor MUST be created before
  `startWriting` (found by the gate, not by luck). Intro/outro insert as
  standalone clips with their own time-keyed aspect-fill transforms + audio.
  `addSoundtrack`: music track trimmed/looped to composition, fade-in/out ramps,
  ORIGINAL audio muted; export's audio reader consumes the AVAudioMix.
- **RenderDecorationsBuilder**: brand settings → full-frame transparent canvas
  (sample logo / uploaded PNG validated / TEXT fallback rasterized), position/
  size/opacity/padding honored; soundtrack/intro/outro resolved from
  `Documents/events/<id>/` (missing → warn + skip, never crash).
- **Model**: `introRelativePath`/`outroRelativePath` (Optionals, decode-safe).
  Settings: "Soundtrack & bumpers" card + tri-lingual licensing guardrail.

**Gate A:** 35/35 — validation matrix, licensing EN/PL/DE, intro/outro duration
math, soundtrack ramps (start silent → 1 → end silent) + original-mute, and a
PIXEL-verified composite (translucent overlay measurably brightens frames).

**Gate B → HANDOFF:** overlay alignment on real spinning footage.

---

## PHASE 6 — Stabilization — ✅ GATE GREEN

**Changed:**
- **StabilizationPreset** (Off/Standard/Cinematic; Cinematic Extended visible-
  but-v2-locked): AV-mode mapping, documented crop ESTIMATES (0/10/20/25%),
  "~N% tighter frame" pre-render preview, operator guidance per preset
  (Off = rigid arms, Standard/Cinematic = vibrating rigs).
- **Honest capture behavior**: the operator's preset decides; unsupported on
  the active format → .off + breadcrumb. The old silent strongest-mode ladder
  (which quietly grabbed cinematicExtendedEnhanced) is GONE — it spent crop the
  operator never approved.
- **Settings**: preset picker with device-gated availability (simulator = Off
  only, honest), amber crop-preview line, red fallback note when the current
  device can't do the chosen preset.
- **Migration**: legacy `stabilizationEnabled` bool → preset (false→off,
  true/nil→standard); new field wins; garbage raw values fall back safely.

**Gate A:** 40/40 — mapping, crop monotonicity + preview text, unavailable-mode
exclusion (incl. v2 lock), migration + effective-preset precedence.

**Gate B → HANDOFF:** real smoothness/crop tradeoff on a vibrating rig (L3).

---

## PHASE 7 — Delivery & reliability (moat) — ✅ GATE GREEN

**Changed:**
- **Deferred-resolve QR (the moat move):** the sign response already carries the
  FINAL public link (idempotent per clientJobId) — the uploader now sets
  `job.publicShareURL` at SIGN time, before the PUT. The guest takes the QR
  immediately; the page resolves when the background upload lands. Network down
  mid-handoff → queue + replay (existing) → same link resolves later. Guest
  NEVER waits on a live upload.
- **DeliveryPolicy** (pure, tested): SMS body fills the operator template AND
  defensively guarantees the link is present (a template without {{link}}
  delivers nothing); size targeting — Best-Quality master >16 MB auto re-exports
  the share copy at Fast Share (loud breadcrumb, never silent).
- **exportPreset** operator setting (Optional, decode-safe); client honors it.
- Delivery instrumentation: existing upload start/success/fail breadcrumbs kept;
  auto-fallback + stabilization/capture crumbs added earlier phases.

**Gate A:** 44/44 — SMS-is-link routing (incl. dropped-placeholder guarantee),
size-fallback thresholds, and the deferred-resolve WIRE CONTRACT (sign response
must carry public_share_url — if the backend ever drops it, this test fails and
the moat regression is caught).

**DoD:** offline-at-handoff → guest holds a QR that resolves post-reconnect
(sign-time link + queue replay). Gate B (real phones, venue wifi) → HANDOFF.

---

## PHASE 8 — Triggers, paywall, perf budget, hardening — ✅ GATE GREEN (FINAL)

**Changed:**
- **TriggerStateMachine** (pure, tested): manual/timer/motion-start flows,
  threshold-gated motion arming with a 1 s sync countdown (hero lands mid-spin),
  illegal transitions ignored (never crash a booth), Bluetooth = v2 seam
  (`BluetoothSpinnerAdapter` protocol stub).
- **Tier gating, sandbox-safe (Decision 2):** PremiumFeature remapped to the
  360 product (watermarkRemoval/allMotionTemplates/customOverlays = Pro;
  whiteLabel/multiDevice = Business). PURE rule `allowed(_:tier:storeConfigured:)`:
  everything unlocked until real ASC products load. Enforced in the render
  path: Free = Boothify watermark + Hero Slow only (breadcrumbed).
- **PerfBudget estimator**: device score (major-number parsing — a test caught
  the naive-prefix bug that would have flagged an "iPhone99" as weak; fail-open
  for unknown devices), template cost model (reverse 2×, overlay 1.2×, bumpers
  1.15×, best 1.25×), verdicts at 3×/6× realtime; amber banner on the 360 hub
  BEFORE the event.
- **Crash recovery in-flight**: active-render marker (set/cleared around
  exports); relaunch after a mid-render death → loud operator notice + crumb;
  raw takes persist on disk for retry.
- **App Store prep (§17):** `PrivacyInfo.xcprivacy` (photos/email/phone/userID/
  crash + UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, no
  tracking), `README.md` at root.
- **HANDOFF.md** — full pack (§14 A–G).

**Gate A (final regression):** 54/54 — trigger machine, gating matrix,
perf-budget verdicts + fail-open, crash marker round-trip, plus all prior
phases' suites.

**Gate B → HANDOFF §A** (device script, 14 ordered items).

## v1 COMPLETE — blueprint §2 scope shipped; v2 items logged, untouched.
