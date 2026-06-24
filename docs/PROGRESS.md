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

## ✅ M2.1 full — Kiosk Mode — DONE (verified)
- `AppState.kioskEventId` locks the app to one event: branded `KioskAttractView` root, tab bar hidden, guest confined to the capture flow (pops back to attract). Keep-awake + ASAM on appear; discreet long-press exit gated by event Lock PIN / confirm. "Start Kiosk Mode" in the event hub; onboarding suppressed in kiosk. Attract screen screenshot-verified on iPhone 17 Pro. (`716f4b2`)

## ✅ No-AI mode — Instant Looks — DONE (verified)
- The booth now works with **zero cloud AI**: `LocalLookProcessor` (12 Core Image looks) + `InstantLooksView` (pick → Save/Print/Share), reachable via "Instant looks · No AI" at the top of the style picker. No Gemini, no upload, offline. Grid screenshot-verified on iPhone 17 Pro. (`00478a4`)
- **No-AI booth routing**: when the operator disables all AI styles, capture goes straight to Instant Looks (skips the cloud picker); green-screen still applies first. Discoverable hint in AI Portraits settings. (`f1bac2f`, `ff65fe0`)
- AI styles still available for when Gemini billing is enabled.
- Minor follow-up: bake the operator brand overlay into Instant Looks save/share (today it's applied on AI results + prints; reusing it needs a small refactor of ResultView's private baker — deferred to avoid risk).

## ✅ Differentiator — Instant Photo Strip — DONE (verified)
- `PhotoStripComposer` renders a classic 4-frame photo-booth strip from ONE capture in multiple on-device looks + event title/date footer — instant, offline, printable/shareable. LumaBooth needs a burst of separate captures for a strip; Boothify generates it from a single photo. "Classic photo strip" entry in Instant Looks; strip screenshot-verified on iPhone 17 Pro. (`24a8448`)

## ✅ Differentiator pack ("better than LumaBooth") — DONE
- **Studio Backdrops** — 8 procedural on-device green-screen backgrounds (no assets). (`be4d568`)
- **CSV lead export** — export survey/guest data from Survey settings (share sheet). (`9fd657e`)
- **Look Reel (MP4)** — AVAssetWriter video cycling one photo through 6 looks. (`bdc937a`)
- **Guest i18n (EN/PL/DE)** — runtime Loc helper on attract/Instant Looks/camera; verified PL live in sim. (`afcdf66`)
- Deferred: live filtered camera preview (#1) — needs the camera pipeline reworked + a real device to verify; not shipped blind.

## Boothify vs LumaBooth — where Boothify now wins
- **22 AI cinematic restyle styles** (LumaBooth: only AI *background removal*).
- **Instant Looks** — 12 on-device looks that work fully **offline / no AI billing** (LumaBooth AI needs internet).
- **Instant photo strip from ONE photo** (LumaBooth: needs multi-capture burst).
- **On-device green screen** (Vision) + **Virtual Attendant TTS** + **face-count guard** before AI.
- Full **Kiosk Mode** (attract + ASAM + PIN exit), **StoreKit 2** tiers, public **/e/<slug>** album, **white-label email**.
- Parity: multi-channel share + offline queue, surveys/disclaimers, AirPrint strips, 360 booth.

## ✅ Polish — brand overlay on no-AI output + on-demand backdrops
- Reusable `BrandOverlayRenderer` bakes the operator logo/mark into Instant Looks single-look output (white-label, print-ready). (`b17343a`)
- On-demand Studio Backdrops inside Instant Looks (segment + composite + brand overlay). (`92de478`)

## ✅ UX heuristic audit (overall 8.7/10) + fixes
- Sanity: both repos build green, clean & synced; no leftover debug hooks; 56 a11y labels, 175 haptics, 84 reduce-motion guards, 20 files with loading/empty/error states.
- Fixed **#1 (Sev 3)**: onboarding quiz now first-run only (was every launch) — verified no overlay when completed. (`0c9a8d1`)
- Fixed **#2 (Sev 2)**: localized the result screen (generating/failed/quota/Retry/Save/Retake/Done) into PL+DE.
- **#3** reviewed = non-issue (both result paths already use ShareLink/system share).
- Minor items also done (`4c083b6`): segmented Instant Looks (Create/Looks/Backdrops headers, verified), one-time kiosk exit-gesture hint, bumped caption contrast (textTertiary/textMuted) for AA. Zero Sev-4 remained.

## ✅ Video stabilization (LumaBooth-grade) — DONE
- Research confirmed LumaBooth's "stabilization" = iOS AVFoundation `preferredVideoStabilizationMode` + operator toggle (adds latency). Implemented: `configureStabilization` now picks the strongest mode the active format supports (cinematicExtended→cinematic→standard→auto), gated by a new Camera setting `stabilizationEnabled` (Optional, nil=on) with toggle + copy; applied to 360 + slow-mo recording. (`b22f129`) — verify on device (recording feature).

## ⚠️ Important verification note — Vision person segmentation is device-only
- `VNGeneratePersonSegmentationRequest` (green screen M1.1 + backdrops) **does not run in the iOS Simulator** — it returns nil there and the photo passes through unchanged. A diagnostic confirmed the backdrop **render + composite pipeline is correct** (produced a full backdrop image when the mask was bypassed); only the ML mask is sim-unavailable. **Must be verified on a real device.** Everything else in this session was screenshot-verified in the sim.

## Remaining (genuinely needs device or human)
- **M1.2** multi-capture (GIF/boomerang/strip) → AI/print pipeline — the ONE big item that needs **real-device camera testing** (simulator uses a placeholder image, so the capture pipeline can't be verified). Existing GIF/boomerang/slow-mo already work (end at a share sheet); the gap is routing them through AI + print-strip layouts. Defer to a device session.
- **M4** observability (needs Sentry DSN — human); shared rate-limit (needs Upstash/Redis — human); final on-device HIG/a11y audit.
- **Entitlement enforcement** — wire `PremiumFeature.canUse` into flows once App Store products exist (human).

## Enforcement note (entitlement gating)
`PremiumFeature.canUse` exists but premium features are NOT yet hard-gated in the
flows — doing so before the App Store products exist would lock the app entirely
(sandbox currentTier is always .free). Wire enforcement once products are live.
