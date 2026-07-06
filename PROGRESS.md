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
