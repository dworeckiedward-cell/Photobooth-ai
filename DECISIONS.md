# DECISIONS — iOS RUN B

(Decisions taken autonomously this run, in addition to the locked-in
DECYZJE from the executive prompt.)

---

## BM0 — Cloud upload as separate phase from render

The FFmpeg render and the cloud upload are intentionally **two phases**,
not one chained call. Render writes a local mp4 + marks status
`.completed`; upload runs after as a background `Task` via
`Booth360CloudUploader.enqueue`.

Why split:
- Operator can navigate to the Result screen / start the next guest's
  recording the instant render finishes. Upload runs invisibly in the
  background.
- Failed upload doesn't undo a successful render — the local file is
  still there to share via AirDrop / Save to Photos, and the queue
  retries the cloud step independently.
- BM1's persistent queue lives entirely in the upload phase; nothing
  about render needs to know about it.

## BM0 — `clientJobId` lifecycle

Generated **once** at `Booth360Job.init` time and reused unchanged on
every retry attempt. The backend's idempotency contract (AM1: lookup
via `metadata->>client_job_id`) means re-running sign → PUT → confirm
with the same id always lands on the same row + storage object.

That's why `Booth360Job.clientJobId` is a `var` only for Codable
synthesis convenience — semantically it's write-once.

## BM0 — Mock share URL kept as optimistic placeholder

Right after render, `publicShareURL` is set to a fake `boothify.app/v/...`
URL. The real one only arrives after `confirm`. We keep the mock so that
the Result screen's QR / Copy Link / ShareLink buttons render with
*something* even if the upload hasn't completed yet — the displayed link
would 404 if scanned immediately, but the UI doesn't crash. Once upload
completes the URL silently swaps to the real backend-minted one.

If we hard-required the real URL upfront the operator would see a
broken Result screen for 5-30s while the upload runs. Bad UX during a
live event.
