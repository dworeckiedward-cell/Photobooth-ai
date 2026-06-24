# Boothify — Progress (execution of docs/EXECUTION-PROMPT.md)

## ✅ M0 — Odblokowanie i „prawda" — DONE
- **M0.1** Gemini 429 → typed `quota_exceeded` + HTTP 429 (not 500); iOS calm "AI limit reached" state. (`d039b95`, `13f1526`)
- **M0.2** Quota fail-open backstop (per-instance brake + block missing-config in prod) + atomic `claim_photo_slot` RPC (migration 14) with route fallback. (`3a293ad`)
- **M0.3** Wired Capture countdown + JPEG quality + Camera mirror-selfie; Effects/Background-Removal marked honestly. (`7a02b38`)
- **M0.4** Backend boot-time env validation (instrumentation); iOS release auth-gate confirmed ON. (`3d689a7`)

## ✅ M1.1 — Real green screen (Vision) — DONE
- On-device `BackgroundReplacer` (VNGeneratePersonSegmentationRequest + CIBlendWithMask): transparent / color / image backgrounds, applied at capture off-main, fallback-safe. Badge AVAILABLE, copy de-mocked. (`3dff1dc`)

## 🟡 M2.1 — Kiosk (core done) 
- `KioskManager`: reference-counted keep-screen-awake wired into camera + slideshow (iPad won't sleep mid-event); ASAM + Guided-Access helpers for managed fleets. (`55e8889`)
- **Remaining:** full in-app nav-lock + attract screen (confine guest to event flow, exit via PIN) — larger nav change, deferred.

## ✅ M2.2 — StoreKit 2 subscriptions — DONE (code)
- `StoreManager` (StoreKit 2): products, purchase, restore, live transaction listener, `currentTier` from entitlements, `PremiumFeature.canUse` gating helper.
- `PaywallView` with plan cards + Restore + App-Review disclosure + empty state.
- Settings "Subscription" row shows the REAL tier (no more hardcoded PRO) and opens the paywall. (`1894cc7`)

---

## TODO(human) — actions only you can do (blocking launch)
1. **Gemini billing** — enable paid tier; set `GEMINI_API_KEY` in `.env.local` + Vercel prod → redeploy. (Else every generation 429s.) — `ai-photobooth/src/lib/gemini/client.ts`.
2. **Apply Supabase migration** `00000000000014_claim_photo_slot.sql` + regenerate types (makes the photo-cap atomic; until then it falls back to the non-atomic check).
3. **App Store Connect**: create auto-renewable subscriptions Starter/Pro/Business (group "Boothify", 14-day trial); add `Boothify.storekit` to the scheme for sandbox testing. Product IDs in `StoreManager.SubscriptionTier.productID`.
4. **Stripe live config** (web/US billing path) per `ai-photobooth/TODO-HUMAN.md`.
5. **Sentry DSN** + shared rate-limit infra (Upstash/Redis) — M4.

---

## ✅ M3.2 — Face-count detection + group UX — DONE
- Vision `FaceDetector` counts faces once off-main; picking an AI style on a 0/2+-face photo confirms "best with one person — continue anyway?". (`bd4a6aa`)

## ✅ M3.3 — Public guest event gallery — DONE
- `/e/<slug>` public album, gated by `share_mode` (grid when public, private notice otherwise); proxy allows `/e/`. (`386993d`)

## ✅ M3.1 — consent — ALREADY ADEQUATE
- Default disclaimer already covers AI processing + sharing + "request deletion at any time" and gates capture. No change needed; revisit only if legal wants jurisdiction-specific copy.

## ✅ M3.3b — email white-label — DONE
- Email send now uses the operator's senderName + subject (from events.settings JSON) → sender display, subject, footer; falls back to event name then Boothify. No contract change. (`15fb805`)

## Remaining roadmap (larger / human-gated)
- **M1.2** multi-capture (GIF/boomerang/strip) → AI/print pipeline — LARGE, touches capture flow; needs real-device testing (simulator has no camera).
- **M2.1 full** in-app kiosk nav-lock + attract screen — touches navigation; careful pass.
- **M4** onboarding/event-templates polish; observability (needs Sentry DSN — human); shared rate-limit (needs Upstash/Redis — human); final HIG/a11y audit + launch gate (`FINISH-PLAN.md` §9).
- **Entitlement enforcement** — wire `PremiumFeature.canUse` into flows once App Store products exist (human).

## Enforcement note (entitlement gating)
`PremiumFeature.canUse` exists but premium features are NOT yet hard-gated in the
flows — doing so before the App Store products exist would lock the app entirely
(sandbox currentTier is always .free). Wire enforcement once products are live.
