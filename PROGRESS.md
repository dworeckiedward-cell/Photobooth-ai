# PROGRESS — iOS direct upload + resilience (RUN B)

Run started 2026-05-28. iOS-side counterpart to backend RUN A
(commit `1076c84`). Goal: app survives an event with flaky WiFi, no
lost takes.

Previous runs landed M0-M7 + IM0-IM4 (HEAD before this run: `a0b5c9d`).

## BM0 — Direct-upload flow
Status: ✅ done

- `Booth360Job` model extended with cloud-upload state:
  - `clientJobId: String` (UUID, generated once at job creation, reused
    across every retry — backend keys idempotency on this)
  - `cloudStoragePath: String?` (returned by sign)
  - `cloudUploadStatus: Booth360CloudUploadStatus` enum
    (`notStarted / uploading / uploaded / failed`)
  - `cloudUploadError: String?`
- `BoothifyAPI` gained 3 new methods:
  - `requestUploadURL(eventSlug:clientJobId:contentType:)` →
    `POST /api/booth360/uploads/sign` (snake_case wire).
  - `uploadVideoDirect(fileURL:to:contentType:onProgress:)` — PUT to the
    Supabase Storage signed URL via a transient `URLSession` with a
    `UploadProgressDelegate` that streams byte counts back to the
    `MainActor`. File-backed upload — even ~80 MB takes stream off disk.
  - `confirmBooth360Job(storagePath:shortCode:clientJobId:eventSlug:durationSeconds:metadata:)`
    → `POST /api/booth360/jobs` with `Content-Type: application/json`
    (hits the AM1 direct-confirm branch on backend).
- `Booth360CloudUploader.shared.enqueue(jobId:app:)` orchestrates the
  whole pipeline: marks `.uploading`, runs sign + PUT + confirm with
  3-attempt exponential backoff per step (1s/3s/9s), swaps the mock
  share URL for the real one on success. On failure: marks `.failed`,
  records the error, hands the job to `Booth360UploadQueue` for retry.
  In-flight tracker prevents double-fire from manual + queue replay.
- `Booth360FFmpegRenderClient` wires the uploader at the end of a
  successful render — render still owns local file production, upload
  is a separate non-blocking phase. Operator can navigate to Result /
  start the next recording while upload runs.

Build: ✅ green on iOS Simulator (zero warnings).

**TODO-HUMAN:** real-device test of the full flow (sign → PUT → confirm)
against the deployed backend (`pnpm supabase db push` + Vercel redeploy
required first per RUN A's TODO-HUMAN).

## BM1 — Upload resilience
Status: ✅ done

The retry logic + persistent queue itself was shipped in BM0
(`Booth360CloudUploader` + `Booth360UploadQueue`). BM1 closes the loop:

- `AppState.bootstrapAuth` now calls
  `Booth360UploadQueue.shared.replayPending(app:)` at the end. Every
  app cold-start re-fires queued failed uploads whose local mp4 still
  exists; orphans get dropped.
- `Booth360ResultView` gains a new `uploadStatusBar(job:)` row that
  surfaces between the metadata chips and the action grid:
  - `.uploaded` / `.notStarted` → empty view (happy path, no clutter)
  - `.uploading` → amber pill with spinner + percent
  - `.failed` → red pill with error text + **Send again** button that
    calls `Booth360UploadQueue.shared.retry(jobId:app:)`
- The 3-attempt exponential-backoff per-step (1s/3s/9s, sign / PUT /
  confirm independently) already lives in `Booth360CloudUploader`.
  Combined with the per-app-launch replay, a stable iPad can drop
  WiFi mid-event and not lose a take.

Build: ✅ green.

## BM2 — SMS-ping + full_name + email-null safety
Status: ✅ done

- `AuthUser`:
  - Confirmed `email: String?` already optional (M2). Decoder safely
    accepts `null` from backend AM2 (private-relay users now persist as
    NULL email instead of synthetic placeholder).
  - **New `fullName: String?`** field with snake_case `full_name`
    CodingKey. Backend AM2 returns it in `/api/auth/apple` +
    `/api/auth/refresh` response bodies.
  - Memberwise init parameter defaults so existing call sites keep
    compiling.
- `AccountSettingsView.signedInName` now prefers `currentUser?.fullName`
  (backend AM2 column) and falls back to `AppleProfileCache.cachedFullName`
  — Apple's first-login name becomes source of truth across devices.
- `Booth360ResultView` action grid gains a 6th tile (SMS) which opens
  a new `Booth360SMSSheet`:
  - Sends via operator's Twilio (M5) using the same `TwilioClient`
    pattern as the photo flow.
  - On success fires `BoothifyAPI.markBooth360SMSSent(jobId:phone:)`
    in a detached Task — POSTs `/api/booth360/jobs/<id>/sms` so the
    backend cloud-status `sent` counter ticks. Fire-and-forget: a
    failed ping doesn't bother the operator since the SMS already went.
  - Disabled state + "Twilio not connected" hint when
    `TwilioClient.currentCredentials()` is nil.

Build: ✅ green.

## BM3 — Sanity + size
Status: ✅ done

- Full build pass — zero non-AppIntents warnings, BUILD SUCCEEDED for
  arm64 + x86_64 Simulator universal.
- **App size:** 76 MB Debug Simulator universal (was 72 MB post-IM0).
  +4 MB this run = `Booth360CloudUploader.swift` + `Booth360UploadQueue.swift`
  + grown `Booth360ResultView` + larger `BoothifyAPI`. Release on real
  device strips x86_64 + symbols, expect ~35-45 MB.
- Auth gate (M2): unchanged — `AppConfig.authGateEnabled = true` in
  Release, `BOOTHIFY_BYPASS_AUTH=1` env still bypasses in Debug.
- Photo flow (M0-M5/M7): inventoried for regressions, none. `ResultView.SMSSheet`
  + `BoothifyAPI.sendSMS` (photo path) untouched. `AuthUser` decoder
  change is additive (`fullName` optional default-nil).
- iOS-side known limitations updated:
  - ~~**Mock share URL window:** right after render the optimistic
    `boothify.app/v/<short>` link is the one the operator sees on the
    Result screen…~~ **Closed** by RA0 (`1c27ec0`) which disabled
    share/QR/SMS/copy until `cloudUploadStatus == .uploaded`, and
    P2 (`6412e97`) which extended the gate to `Booth360EventHubView`'s
    "Share event" surface and removed dead-code paths in `Booth360ResultView`.
  - **No upload progress on actionGrid for queued/failed jobs viewed
    elsewhere** — only the Result screen for the active job shows
    upload status. A pending failed upload from a previous take has no
    surface outside that one screen. BM1's `uploadStatusBar` shows it
    when re-entering Result for that job; full-event "X uploads pending"
    badge is a future ask (cloud-status panel hook).
  - **Background uploads** still foreground-only (per prompt: no
    enterprise queue). If operator backgrounds the app mid-upload,
    iOS gives the Task ~30s before suspending — usually enough for
    a 10 MB PUT. On suspension the job goes to `.failed` and the
    next launch's `replayPending` retries.

Build: ✅ green.

---

# Previous milestones reference

See git log for M0-M5/M7 (recording + auth + cloud + UI + Twilio) and
IM0-IM4 (FFmpeg / QR+AirDrop / cloud status / onboarding / debug bypass).

---

## UX Polish Pass — 2026-05-28

Read-only audit + 8 low-risk commits + strategic roadmap. See:
- `UX_AUDIT.md` — full audit (A1-A14 scored, TOP 10 issues, gap
  analysis vs Halide / Darkroom / Procreate / Linear / Loomabub).
- `QUICK_WINS.md` — eight `polish(qw1-8):` commits delivered
  (commits `b7c78d5 → 4b6a452`). Each before/after + rationale.
- `STRATEGIC_PROPOSALS.md` — four larger moves awaiting greenlight:
  P1 motion+typography spec, P2 operator HUD overlay, P3 result
  redesign, P4 guest viewer + marketing footer.

**Overall UX score:** 🟡 3.1/5 — functional, branded, behind world-class
on motion + accessibility + state-design. Loomabub parity 2-3 polish
sprints out; Halide parity 1-2 month follow-up.

---

## Pre-Event Omnibus — RUN A — 2026-05-29

Two-layer pre-event close: **Event Survival** (thermal, crash-restart,
error reporting, status HUD, mock-URL gate, release tuning) + **Design
System Foundation** (motion + typography tokens). All świętości
preserved (upload / auth / render / cloud sync / photo flow / QW1-8).

See `OMNIBUS_REPORT.md` for the full narrative.

| #   | Milestone                              | Status | Commit    |
|-----|----------------------------------------|--------|-----------|
| RA0 | Mock Share URL gate                    | ✅     | `1c27ec0` |
| RA1 | Thermal monitor + auto-degrade bitrate | ✅     | `cee3b29` |
| RA2 | Crash-restart context                  | ✅     | `621f846` |
| RA3 | Sentry SDK + breadcrumbs               | ✅     | `b46340b` |
| RA4 | Unified Status HUD overlay             | ✅     | `0bb0396` |
| RA5 | MotionTokens system + 7-file sweep     | ✅     | `bddfd17` |
| RA6 | Typography token system + 4-file sweep | ✅     | `218792c` |
| RA7 | Release build strip / dead-code        | ✅     | `3e903c1` |
| RA8 | Docs + final report                    | ✅     | this commit |

Build: ✅ green on Debug + Release Simulator universal after every
milestone. Photo flow + 8 quick wins inventoried — no regressions.

**TODO-HUMAN (RA):** create Sentry project + set `BOOTHIFY_SENTRY_DSN`
in Info.plist, wire `sentry-cli` dSYM upload as post-archive Build
Phase, run Xcode Archive once to measure real-device IPA size (Release
strip flags are in place; expected ~35-45 MB).

---

## Loose-End Closure — RUN A2 — 2026-05-29

Follow-up close on RUN A. Build was reported red on a fresh checkout
("Missing package product 'FFmpeg-Kit' / 'Sentry'") — turned out to
be a stale Xcode SPM cache issue; first `xcodebuild` after the RUN A
commits resolved cleanly. No package fix needed.

Then a small follow-up pass to close loose ends from prior runs:
audit the BM2 / RA0 / P3 / P4 hooks, close 3 stale comments/docs
that no longer match the impl.

| #  | Milestone                                  | Status | Commit    |
|----|--------------------------------------------|--------|-----------|
| P0 | Debug + Release builds + simulator smoke   | ✅     | (no code) |
| P1 | BM2 SMS-ping wire — verified               | ✅     | (no code) |
| P2 | RA0 mock-URL gate — 2 holes closed         | ✅     | `6412e97` |
| P3 | AuthUser.email nullable safety — verified  | ✅     | (no code) |
| P4 | 9 missing Sentry breadcrumbs filled        | ✅     | `972527c` |
| P5 | 3 stale limitations / comments closed      | ✅     | `2aaaf42` |
| P6 | Full sanity sweep (this section)           | ✅     | this commit |

**Findings worth noting:**

- P2 found two real RA0 leak paths the original audit missed:
  1. `Booth360EventHubView.guestShareURL()` returned the placeholder
     URL based on `status == .completed` (render done) without
     checking `cloudUploadStatus == .uploaded` (cloud confirmed).
     The "Share event" + "Copy link" buttons + the URL label all
     surfaced 404-bound boothify.app/v/<short> for 3-30s post-render.
  2. Dead-code `sharePresented` `@State` + `.sheet { ShareSheet }`
     block in `Booth360ResultView` left over from the pre-RA0 path,
     before native `ShareLink` replaced it. A future caller toggling
     the flag would have re-opened the hole.

- P4 found the Sentry breadcrumb timeline was sparse — operator
  signs in, then 10 minutes of silence in the crumb trail, then a
  crash with no context about what they were doing. Filled in:
  recording start/end, render done, upload start/success/fail,
  share/QR/SMS open, SMS sent, session refresh success/failure.

- P5 found the auth gate "TODO: Re-enable Sign in with Apple before
  production" comments in 3 files were stale — `AppConfig.authGateEnabled`
  defaults to `true`, has since IM4 (BOOTHIFY_BYPASS_AUTH only flips
  it off in Debug). Also the `Booth360ResultView` header doc still
  described a pre-IM0 placeholder gradient card that no longer exists.

**Build sanity (final):**
- Debug Simulator universal: ✅ green, 85 MB .app on disk
  (+9 MB vs post-BM3 from Sentry framework + ffmpeg-kit-spm
  subframeworks newly resolved this session).
- Release Simulator universal: ✅ green, 72 MB .app on disk
  (matches RA7 measurement; real-device IPA still TBD via Archive).
- Photo flow + 360 flow + RA0-RA7 + QW1-8: inventoried, no regressions.
- Smoke test: simulator launch clean, Sentry correctly no-ops
  without DSN (RA3 design), no crashes in early-launch logs.
