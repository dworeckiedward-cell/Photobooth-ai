# Boothify — Progress (execution of docs/EXECUTION-PROMPT.md)

## M0 — Odblokowanie i „prawda" — IN PROGRESS

### ✅ M0.1 — Gemini 429 → typed quota_exceeded + iOS UX
- Backend (`ai-photobooth`): new `GenerationError` kind `quota_exceeded`; classify upstream 429/RESOURCE_EXHAUSTED; skip retries; route returns **429** (not 500) for quota. (commit `d039b95`)
- iOS: `ResultView.failedView` shows calm amber "AI limit reached" for quota_exceeded. (commit `13f1526`)

### ✅ M0.3 — Reconcile dead Settings (iOS) (commit `7a02b38`)
- Countdown reads `event.capture.countdownFirstPhoto` (was hardcoded 3; 0 snaps).
- JPEG quality reads `event.capture.quality` (was 0.85).
- Mirror selfie honors `event.camera.mirrorSelfie` (was always on) — across preview/photo/video/boomerang.
- Effects + Background Removal badged **DEMO** (were AVAILABLE) until real pipelines ship (M1.1).

### ✅ M0.2 — Generation race fix + quota backstop (backend)
- Quota backstop in `quota.ts`: per-instance daily attempt brake (`GEMINI_INSTANCE_DAILY_CAP`, default 1000) + **block missing-config in production** (was unbounded fail-open).
- Atomic photo-slot claim: migration `00000000000014_claim_photo_slot.sql` (advisory lock + SELECT FOR UPDATE) + route calls `claim_photo_slot` RPC with graceful fallback to the legacy check.

### ⏭ M0.4 — env validation + release flags — NOT STARTED
- Backend: boot-time env schema validation (~20 vars).
- iOS: confirm `AppConfig.authGateEnabled` ON in Release.

---

## TODO(human) — actions only you can do (blocking launch)
1. **Gemini billing** — enable paid tier on the Google project behind `GEMINI_API_KEY`; set the key in `.env.local` AND Vercel Production → redeploy. (Without this every generation 429s.) — see `src/lib/gemini/client.ts`.
2. **Apply migration** `00000000000014_claim_photo_slot.sql` to Supabase (supabase db push / Management API), then regenerate types. Until applied, the route falls back to the non-atomic check.
3. **App Store Connect / Stripe** — for M2 monetization (StoreKit products; Stripe live config per `ai-photobooth/TODO-HUMAN.md`).
4. **Sentry DSN**, shared rate-limit infra (Upstash/Redis) — for M4.
5. Decide monetization classification (3.1.3c vs StoreKit) — recommendation in `FINISH-PLAN.md` §5.

---

## Next up
- M0.4 (env validation + release flag), then **M1** (green screen, multi-capture → AI/print).
