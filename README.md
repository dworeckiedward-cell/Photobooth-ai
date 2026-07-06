# Boothify 360

Premium, iOS-native, **360-only** photo-booth render engine for event operators.
Operator mounts an iPhone on a spinning arm; guest steps on; the app captures at
high fps, renders a branded, motion-templated MP4 **entirely on-device**
(AVFoundation/VideoToolbox — no cloud AI, no FFmpeg, no per-render cost) and
delivers it via QR/link/email/AirDrop with an offline-safe queue.

## Build & run

```bash
# gate = build + full test suite (the only merge criterion)
./scripts/gate.sh

# or manually
xcodebuild -scheme Photobooth-ai -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- Xcode 26+, deployment target **iOS 17.0** (device-verified: NEEDS-DEVICE).
- Backend: `ai-photobooth` (Next.js/Supabase) — `BOOTHIFY_API_BASE_URL` in build
  settings. The app degrades gracefully (queues + retries) when it's absent.
- Simulator has no camera: recording falls back to a mock pipeline; the RENDER
  engine is fully testable in sim via synthetic clips (see
  `Photobooth-aiTests/TestVideoFactory.swift`).

## Status — blueprint v4 execution

All phases 0–8 executed, every Gate A green (54 tests). See:
- `PROGRESS.md` — per-phase log (what changed, gate status, risks)
- `HANDOFF.md` — device test script, repair map, NEEDS-DEVICE list
- `DECISIONS_LOG.md` / `ASSUMPTIONS.md` — every non-trivial choice
- `BACKEND_CONTRACT.md` — existing API contract + gaps for the backend owner
- `PRIVACY.md` — GDPR posture; `Photobooth-ai/PrivacyInfo.xcprivacy` — manifest

v2 backlog (deliberately not built): 240 fps Pro Mode, APNG overlays, Cinematic
Extended stabilization, Bluetooth spinner integrations, multi-device, SMS-link
channel.
