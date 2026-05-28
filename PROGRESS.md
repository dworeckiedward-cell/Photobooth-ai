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
Status: ✅ partial (queue + uploader retry shipped in BM0; UI surfaces below)

## BM2 — SMS-ping + full_name
Status: _pending_

## BM3 — Sanity + size
Status: _pending_

---

# Previous milestones reference

See git log for M0-M5/M7 (recording + auth + cloud + UI + Twilio) and
IM0-IM4 (FFmpeg / QR+AirDrop / cloud status / onboarding / debug bypass).
