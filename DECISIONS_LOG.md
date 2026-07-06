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
