# Boothify 360 — Backend Contract (existing + gaps)

The 360 backend contract ALREADY EXISTS in `ai-photobooth` (Next.js/Supabase).
This documents what the app calls today, the record shapes it expects, and the
gaps the human must fill. Do not redesign from scratch.

## Existing endpoints (verified in both repos)

| Endpoint | Method | Used by (iOS) | Purpose |
|---|---|---|---|
| `/api/booth360/jobs` | POST (multipart) | `BoothifyAPI.swift` (~:208) | Create job + upload raw recording |
| `/api/booth360/jobs` | POST (JSON body) | `BoothifyAPI.confirmBooth360Job` (~:355) | **Confirm** a signed upload — same path, different content-type branch (AM1), NOT a separate route |
| `/api/booth360/jobs/[id]` | GET | job polling | Job status + `publicShareUrl` |
| `/api/booth360/jobs/[id]/sms` | POST | `Booth360SMSSheet` | Flag that iOS already sent the SMS |
| `/api/booth360/uploads/sign` | POST | `BoothifyAPI.requestUploadURL` (~:274) | Signed upload URL (sign → PUT → confirm) |
| `/api/auth/apple`, `/api/auth/refresh`, `/api/auth/account` | POST/DELETE | AuthClient | Sign in with Apple, refresh, account deletion (incl. Apple token revoke) |
| `/api/events` + `/api/events/recent` + `/api/events/[slug]` | POST/GET | event CRUD | Event lifecycle |
| `/e/{slug}` | page | QR / gallery link | Public event gallery (web) |

**Public 360 link** = `publicShareUrl` returned by the jobs API.
`/p/{id}` is the PHOTO result page — do not use for 360.

## Job record shape the app reads (Booth360JobDTO, APIModels.swift)

`id`, `status` (uploading/queued/processing/completed/failed), current step,
progress, `publicShareUrl`, video URLs, timestamps. Upload idempotency via
`client_job_id` minted once on device and reused on retries.

## GAPS — human must deliver (see also OUT OF SCOPE, blueprint §16)

1. **GAP #1 — `GET /api/booth360/jobs` (collection listing) does not exist.**
   Job lists live only in-memory (`AppState.booth360Jobs`) → operator loses
   clip history on reinstall/device change. **Prerequisite for the persistent
   360 gallery; needed before Phase 7.** Suggested shape:
   `GET /api/booth360/jobs?eventId=…` → `[{ id, event_id, status, public_share_url, created_at, duration_s, size_bytes }]`, bearer-authed, owner-scoped.
2. **Retention / delete:** no DELETE for a 360 clip, no retention policy.
   Needed for GDPR delete path (PRIVACY.md).
3. **CDN/storage provisioning** for hosted clips (Section 3): clips are
   8–15 MB; links/QRs must resolve from stable hosting.
4. **Supabase migration 15 (`apple_refresh_token`)** — apply to prod (auth).
5. **Supabase migration 14 (`claim_photo_slot`)** — governs the AI-photo slot
   limit. After the 360-only cut it is **likely obsolete**; review before
   applying blindly.

## Degradation contract (app side, enforced by Phase 2)

Backend absent/unreachable → app queues (Booth360UploadQueue) and retries;
QR/links resolve once upload completes; UI never blocks a guest on a live
upload; no crash on missing tables/endpoints (feature-detect).
