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
