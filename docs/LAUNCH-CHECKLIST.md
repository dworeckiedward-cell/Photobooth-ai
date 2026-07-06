# Boothify — App Store Launch Checklist (verified against code)

Mapped from the iOS App Launch Checklist. Each row is **verified in the codebase**,
not assumed. Status: ✅ done · ⚠️ needs human/credentials · ❌ code gap (fixable now).

## Blockers — nothing ships until these are green

| # | Item | Status | Evidence / What's needed |
|---|------|--------|--------------------------|
| B1 | **AI value loop works** (photo → AI portrait) | ⚠️ | Gemini returns 429 (free tier). Enable **paid billing** + set `GEMINI_API_KEY` local + Vercel. This is the video's "server 500" — the app looks broken until it's on. |
| B2 | **Backend reachable from iOS** | ⚠️ | `BOOTHIFY_API_BASE_URL` must point at a running webapp (Supabase keys live). Without it: no login, empty events. |
| B3 | **Supabase migration 14** applied + types regenerated | ⚠️ | `00000000000014_claim_photo_slot.sql` — makes the photo-cap atomic. |
| B4 | **StoreKit products created** in App Store Connect + sandbox-tested | ⚠️ | Product IDs already in `StoreManager.SubscriptionTier.productID`. Reviewer must be able to purchase. |
| B5 | **Tested on a real device** end-to-end | ⚠️ | Nothing is device-verified: camera, green screen, live preview, capture pipeline, Event Wall. Simulator can't. |

## Apple rejection reasons — found in code

| # | Item | Status | Evidence |
|---|------|--------|----------|
| R1 | **Sign in with Apple token revocation on account delete** | ❌ | `api/auth/account/route.ts` deletes the user + `revokeAllSessions`, but **never calls `appleid.apple.com/auth/revoke`**. Apple audits this. Needs: capture the auth code at sign-in → exchange for refresh token → store it → on delete, sign an Apple client secret (JWT via .p8 key) and POST to the revoke endpoint. Needs Apple key (.p8), Key ID, Team ID. |
| R2 | **Privacy Policy + Terms (EULA) links on the paywall** | ❌ | `PaywallView.swift` has Restore + auto-renew text but **no Privacy/Terms links** (guideline 3.1.2). Fixable now once the URLs exist. |
| R3 | **Privacy Policy / Terms / Support pages** (real URLs) | ❌ | Don't exist. Global Settings rows are currently honest info rows (not dead links) but need working URLs before submit. Plan: host `/privacy`, `/terms`, `/support` on the webapp. |
| R4 | **iPad screenshots** | ⚠️ | `TARGETED_DEVICE_FAMILY = 1,2` (iPhone **and** iPad — correct for a photobooth). Therefore **real iPad screenshots are mandatory** — never stretch iPhone ones. |
| R5 | **Entitlement enforcement** | ⚠️ | `PremiumFeature.canUse` exists but isn't gating flows (sandbox tier is always `.free`, so gating now would lock the app). Wire once products are live (B4). |

## Already done — verified ✅

| Item | Evidence |
|------|----------|
| Restore Purchases | `StoreManager.restore()` + button in `PaywallView` |
| Auto-renew disclosure on paywall | `PaywallView.swift:38` ("renews automatically… 14-day free trial") |
| Account deletion in-app | `SettingsMVPViews` Delete account → `DELETE /api/auth/account` (hard-delete + cascade) |
| Sign in with Apple as the only social login | No Google/FB → guideline 4.8 satisfied (no extra private option required) |
| App auth gate ON in release | `AppConfig.authGateEnabled` = true in `#else` (release) |
| Onboarding exists, first-run only | `OnboardingQuiz`, suppressed in kiosk |
| Guest localization EN/PL/DE | `Loc.t` across attract / camera / Instant Looks / result |
| Permission usage strings | NSCamera / NSPhotoLibrary / NSFaceID present in project |

## What Claude can do now (no credentials needed)

1. **R2 + R3**: generate `/privacy`, `/terms`, `/support` pages on the webapp (solid boilerplate — **must be reviewed before submit**), then wire those URLs into the paywall (R2) and the Settings rows (R3).
2. **R1 code path**: implement the Apple token-revocation flow (auth-code capture + exchange + revoke). Ships dormant until you add the Apple .p8 key / Key ID / Team ID.
3. **Paywall polish**: pricing clarity (annual price prominent over weekly breakdown — a real past rejection reason in the checklist).

## What only you can do

Gemini billing (B1) · env/base URL (B2) · Supabase migration (B3) · App Store Connect products + sandbox (B4) · real-device test (B5) · Apple Developer enrollment + agreements/tax/banking · iPad screenshots (R4) · legal review of the generated Privacy/Terms.
