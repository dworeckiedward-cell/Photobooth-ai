# Boothify 360 — Privacy / GDPR posture (blueprint §8)

360 clips are identifiable video of guests (EU-relevant, RODO/GDPR).

## Consent
- Consent mechanism EXISTS (DisclaimerSettings: `requireConsentBeforeCapture`,
  consent log per event) and must gate capture when enabled. KEEP; verify it
  stays enforced on the 360 recording path (Phase 3 regression).

## Data flows
- Raw capture: on-device only; purged after render completes (retention policy,
  Phase 2 storage lifecycle).
- Rendered master: on-device, capped per event; uploaded via sign→PUT→confirm
  to the operator's backend for link/QR delivery.
- Delivery details (email/phone a guest enters): used to deliver that clip only.
- No PII in URLs (public links are opaque ids/slugs). Keep it that way.
- Analytics/observability: Sentry crash data only, `sendDefaultPii = false`,
  DSN off by default.

## Delete path
- Operator account deletion: in-app (Settings → Account), hard-deletes account
  + events + clips, revokes Apple token (backend implemented; Apple creds are
  the human's job).
- Per-clip delete: **backend gap** (see BACKEND_CONTRACT.md #2). Until it
  exists, deletion requests go through the operator/support.

## Permission strings (present in build settings; localized copy = EN today)
Camera, Microphone, Photo Library add/read, Face ID. If Bluetooth spinner
support (v2) lands, add NSBluetoothAlwaysUsageDescription BEFORE shipping v2.

## App Store artifacts still to produce (Phase 8 / §17)
- `PrivacyInfo.xcprivacy` (required-reason APIs, data types).
- App Privacy labels update post-cut (docs/APP-REVIEW.md describes the PRE-cut
  labels — photos/AI wording must be revised to video/360 when the cut lands).
