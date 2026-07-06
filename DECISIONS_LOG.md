# Boothify 360 — Decisions Log (blueprint v4 execution)

## Phase 0

1. **Dropped the unused `app: AppState` parameter from `Booth360UploadQueue.enqueue`.**
   Why: constructing a second `AppState` inside the XCTest host crashes the runner
   (malloc double-free — the host app already owns its AppState). The parameter was
   `app _:` (never read), so removing it is a zero-behavior change that makes the
   KEEP queue testable. Call site in `Booth360CloudUploader` updated.
   KEEP-conflict note per Section 5: minimal change, logged here.

2. **Sentry DSN task closed as already-done.** `SentryClient.start()` already reads
   `BOOTHIFY_SENTRY_DSN` from Info.plist and no-ops cleanly when unset. Consumed
   as-is (blueprint rule 6: don't rebuild what exists).

3. **Kept the `INFOPLIST_KEY_BOOTHIFY_API_BASE_URL` Release value** pointing at the
   existing Vercel deploy — backend prod config is the human's job (Section 16);
   changing it is out of scope.

4. **Shared scheme created** (`xcshareddata/xcschemes/Photobooth-ai.xcscheme`) because
   the project had only auto-generated schemes; `xcodebuild test` needs a deterministic
   TestAction for the gate script.

5. **Stale FFmpeg doc-comments in ThermalMonitor rewritten** (render-client-neutral)
   so no comment claims FFmpeg is the current pipeline. Historical mentions elsewhere
   (e.g. "since IM0" notes) left — they describe history, not current architecture.

## Phase 1

6. **Hub duality resolved: `Booth360EventHubView` is THE hub.** Blueprint 4.D said
   "repoint EventHubView", but the 360 flow already lands on Booth360EventHubView
   (from Booth360Landing) and it is 360-native (job stats, recordings, share). Kept
   it, ported the kiosk button into it, and CUT EventHubView. Symmetric with the
   4.G landing decision. Crash-restore + calendar repointed to booth360 routes.
7. **4.A QRSheet extraction became moot** — its only users (ResultView, EventHubView)
   are both cut and the 360 hub has its own Booth360QRSheet. Extracted `ShareSheet`
   instead (genuinely shared with KEEP files).
8. **Kept `Booth360EventRow` instead of porting `RecentEventRow`** — the 360 row shows
   video counts (better fit); porting would duplicate.
9. **OnboardingQuiz cut, not simplified** — its one real effect (seeding first-event
   settings) is superseded by the ported EventTemplate chips.
10. **Test-send (Delivery Status) removed, not stubbed** — it depended on the photo
    pipeline. Channel status list stays; per-channel tests return in Phase 7 against
    360 links. Honest footer copy, no dead buttons.
11. **"Album privacy" (share_mode) card cut** — it governs the WEB photo album
    (/e/slug); 360 public links are per-clip publicShareUrl. Event.shareMode stays on
    the wire model for decode compat.
12. **VirtualAttendant + CaptureSettings/CameraSettings sections kept in the model**
    (camera prefs are 360-relevant; attendant re-wires to the 360 countdown later).
    PrintPaperSize-type orphan enums swept only where they blocked compile.

## Phase 2

13. **GAP #1 declared closed** — endpoint found at
    `/api/events/{slug}/booth360-jobs` (both sides existed; nobody called it).
    Hydration merge policy: LOCAL job always wins (knows file URLs + upload
    bookkeeping); server-only jobs inserted; share URL backfilled onto local
    jobs missing it. Unknown server status strings map to .failed with the raw
    value in errorMessage — loud, not silent.
14. **Master cap = count-based (50/event), not size-based** — simpler to reason
    about at an event; size pressure is handled by the low-storage responder.
    Caps configurable via StorageLifecycle init.

## Phase 3

15. **Upload-initiation regression found & fixed.** Removing
    Booth360FFmpegRenderClient (Phase 0) silently removed the ONLY call that
    kicked Booth360CloudUploader after a render. Passthrough never enqueued.
    Native client restores it. Window: phase-0..2 tags (no user-facing release).
16. **Mock share links eliminated.** Passthrough fabricated
    boothify.app/v/… URLs. Native client leaves publicShareURL nil until the
    uploader confirms the real one — delivery honesty is the moat.
17. **Raw purge targets job.rawVideoLocalURL** (recorder's Documents path), not
    only the StorageLifecycle canonical path — recordings pre-date the new
    layout. Raw KEPT on render failure (retry without re-shoot).
18. **E2E size floor = "non-empty/valid" (20 KB), not the 8–15 MB window** —
    synthetic solid-color frames legitimately compress far below the average
    bitrate; the marketing window is asserted in Phase 7 on realistic footage.

## Phase 4

19. **Reverse = real chunked re-encode** (0.2 s chunks, upright intermediates),
    not a fake. Reversed spans are silent by design — reversed audio is noise
    and Phase 5's soundtrack covers the whole timeline. ReverseBounce's back
    pass runs at 0.8× so the bounce reads deliberate.
20. **Ramp step = 0.1 s source time** — 10 sub-segments/s of ramp; smooth at
    30 fps output without exploding composition complexity.
21. **Template/curve stored as raw-value Optionals on AI360Settings** so
    pre-Phase-4 blobs decode untouched (same pattern as stabilizationEnabled).

## Phase 5

22. **Per-frame CI compositing instead of CoreAnimationTool** — the tool is
    ignored on the AVAssetReader path; GPU CIImage composite into pool buffers
    keeps the offline pipeline honest and testable.
23. **Adaptor-before-startWriting**: AVAssetWriterInputPixelBufferAdaptor
    created after startWriting corrupts the heap ("freed pointer was not the
    last allocation"). Gate caught it; creation reordered.
24. **Soundtrack mutes original audio** (booth convention; reversed spans were
    silent anyway). Ducking as an operator knob can come later without engine
    changes (mix params).
25. **Text-fallback branding is rasterized** so overlay parity holds across
    logo sources; opaque FULL-FRAME uploads rejected, small opaque logos are
    fine (canvas supplies transparency).

## Phase 6

26. **Silent strongest-mode ladder removed.** Pre-Phase-6 code auto-selected the
    strongest supported stabilization when "ON" — spending frame crop the
    operator never saw. §7.4's honesty rule wins: the chosen preset or .off,
    never a silent upgrade. Legacy true/nil migrates to STANDARD (middle), not
    strongest, for the same reason.
27. **Cinematic Extended ships v2-locked but visible** — operators see the
    roadmap; supportedPresets() hard-excludes it from v1 selection.

## Phase 7

28. **publicShareURL set at SIGN, not confirm.** The sign endpoint mints the
    final short-code link idempotently — waiting for confirm only delayed the
    guest for zero correctness gain. Upload status still gates "delivered"
    messaging; the link itself is handed out immediately.
29. **Size fallback re-exports the SHARE copy at Fast Share when a Best master
    exceeds 16 MB** — master quality is the operator's choice, deliverability
    is the guest's guarantee.
