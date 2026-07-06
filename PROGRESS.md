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
