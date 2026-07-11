# Boothify 360 — HANDOFF PACK (blueprint §14)

Every automated gate (Phases 0–8) is GREEN: 54 tests, build at iOS 17.0.
What remains is exactly what a simulator cannot verify. Work through §A on real
hardware; when something fails, §B maps the symptom to the fix location.

---

## A. Ordered device test script

Run on: one WEAK device (iPhone 11/XR-class or 2020 iPad) + one modern iPhone.

1. **Launch & entry** — app opens to the 360 landing (Booth tab).
   *Expected:* create-event card with template chips; no AI/photo surfaces
   anywhere. *Failure looks like:* photo-era screens or dead routes.
2. **Create event via chip** — tap "Brand Event", Start session.
   *Expected:* name seeded, event configured (consent ON, survey ON), lands on
   recording screen. Consent sheet appears BEFORE camera (GDPR gate).
   Declining pops back.
3. **120 fps capture** — record a 2.5 s spin (rear camera).
   *Expected:* Sentry breadcrumb `high-fps fallback` ONLY if the device can't
   do 120 (Settings → verify achieved fps in logs). *Failure:* silent 30 fps
   with no breadcrumb → `CameraController.configureHighFrameRate`.
4. **Hero Slow render** — default template, Fast Share.
   *Expected:* MP4 completes within ~3× clip length on a modern phone;
   1080×1920, ~8–15 MB for 8–10 s; ONE smooth slow-mo beat, eased in/out, no
   stutter at ramp joins. *Failure:* choppy hero → §B-1.
5. **Reverse Bounce render** — forward → reverse, deliberate bounce.
   *Expected:* reverse is real (motion runs backwards), render takes ~2× Hero
   Slow (expected cost). *Failure:* §B-2.
6. **Overlay + soundtrack** — enable Brand Overlay (sample logo, bottom-right)
   + attach a music file on the recording screen.
   *Expected:* logo crisp (not stretched), music fades in/out, original audio
   muted. *Failure:* §B-3.
7. **Deferred-resolve QR (THE moat test)** — turn WiFi OFF, record + render,
   open the result, scan the QR with a phone on cellular.
   *Expected:* QR exists IMMEDIATELY (link known at sign… wait — no network
   means sign hasn't run: QR appears once the device reconnects and the queued
   sign+upload fire; the guest can also AirDrop the local file right away).
   Turn WiFi ON → within ~a minute the same link resolves to the clip.
   *Failure:* guest blocked on upload, or link never resolves → §B-4.
8. **Kiosk non-blocking** — Start Kiosk Mode, record as a guest, tap
   "Next guest" during processing.
   *Expected:* attract screen returns instantly; previous clip finishes in
   background (check the hub). PIN long-press exits kiosk.
9. **Storage & thermal** — fill the device to <2 GB free; try recording.
   *Expected:* clear "Not enough storage" alert, no crash. Run 10+ renders
   back-to-back on the weak device: thermal breadcrumbs appear, UI stays alive.
10. **Crash recovery** — force-kill the app mid-render (swipe up during
    Processing). Relaunch.
    *Expected:* operator notice "A 360 video was interrupted mid-render…";
    raw take still under `Documents/events/<id>/`; no broken render state.
11. **Perf-budget banner** — on the WEAK device set Reverse Bounce + Best
    Quality + overlay + bumpers.
    *Expected:* amber gauge warning on the event hub BEFORE recording.
12. **Stabilization** — on a vibrating rig try Off/Standard/Cinematic.
    *Expected:* picker shows only device-supported presets; crop preview text
    matches the visible framing loss (calibrate §B-5).
13. **iOS 17 runtime** — install on a physical iOS 17.x device; smoke-test
    items 1–4. (Compile-verified only so far.)
14. **Tier gating dry-run** — once ASC products exist and load in sandbox:
    Free account → renders carry the Boothify watermark + templates lock to
    Hero Slow; Pro unlocks both. BEFORE products exist the app must be fully
    unlocked (verify nothing gates).

## B. Repair map (symptom → location)

1. **Choppy/steppy hero** — capture fps miss (breadcrumb `high-fps fallback`)
   → `CameraController.configureHighFrameRate`; or ramp step too coarse →
   `MotionTemplates.rampStepSeconds` (0.1 → 0.05); or clamp engaged on a low-fps
   capture (breadcrumb `hero speed clamped`) — that one is honest physics.
2. **Reverse wrong/glitchy** — `Booth360ReverseEncoder` (chunk size 0.2 s;
   PTS re-stamping); bounce speed at `MotionTemplates.reverseBounce` (0.8×).
3. **Overlay soft or misplaced** — canvas rasterization
   `RenderDecorationsBuilder.overlayCanvas` (position/size/padding math);
   compositing `Booth360RenderEngine.export` (CI pipeline). Audio fades →
   `addSoundtrack` (fade 0.8 s).
4. **Delivery** — link minted at SIGN (`Booth360CloudUploader` — publicShareURL
   set right after `requestUploadURL`); offline queue `Booth360UploadQueue.replayPending`
   (fires on launch + network restore); size fallback `DeliveryPolicy` (16 MB).
5. **Stabilization crop feels wrong** — estimates in
   `StabilizationPreset.estimatedCropFraction` (documented approximations —
   recalibrate against the rig).
6. **Renders miss the handoff window** — thresholds in `PerfBudget.verdict`
   (3×/6× realtime) + device table `deviceScore`.

## C. Instrumentation

- **Debug render without a spinner:** run
  `Photobooth-aiTests/RenderEngineTests` — `TestVideoFactory` renders synthetic
  clips through the FULL pipeline in sim; outputs land in the sim's tmp dir for
  visual inspection.
- **Breadcrumb trail (Sentry, once DSN set):** `recording started`,
  `high-fps fallback`, `hero speed clamped`, `stabilization unsupported`,
  `upload start/success/failed`, `auto fast-share fallback`,
  `template gated`, `render interrupted by relaunch`.
- Gate: `./scripts/gate.sh` (build + 54 tests).

## D. NEEDS-DEVICE (grouped; each ties to §A)

See `NEEDS_DEVICE.md`. Highlights: real 120/240 capture (§A3), render quality +
size window on real footage (§A4–6), venue-wifi delivery (§A7), kiosk loop
(§A8), thermal/storage under load (§A9), crash recovery (§A10), stabilization
crop (§A12), iOS 17 runtime (§A13).

## E. Open assumptions

See `ASSUMPTIONS.md` (file+line). Key: crop estimates are approximations;
perf-budget thresholds are heuristics; gate destination is an iOS 26 sim.

## F. Human checklist (blueprint §16 — launch blockers outside the app)

1. Backend prod deploy + `BOOTHIFY_API_BASE_URL`; CDN/storage for clips.
2. Supabase migration 15 (apple_refresh_token); DECIDE on 14 (likely obsolete).
3. Apple keys (.p8/KeyID/TeamID) → token revocation activates.
4. Sentry DSN (`BOOTHIFY_SENTRY_DSN` Info.plist key).
5. ASC subscription products (Starter/Pro/Business) + sandbox purchase test;
   gating self-activates when products load (§A14).
6. App Privacy labels rewrite for 360 (docs/APP-REVIEW.md describes the pre-cut
   app — photos/AI wording must become video/360), iPad screenshots, review
   notes update, legal review of web privacy/terms.
7. Backend gaps (BACKEND_CONTRACT.md): per-clip DELETE + retention policy.

## G. Backend contract

`BACKEND_CONTRACT.md` — existing endpoints (verified both sides), job schema,
degradation contract, remaining gaps.

### F+ — Deep links (added post-audit, needs the Apple Team ID)
The app now handles universal links (`/e/{slug}` → event hub,
`/v/{short}` → result; ignored in kiosk mode) and declares
`applinks:ai-photobooth-rust.vercel.app`. For links to actually open the
app, the backend must serve
`https://ai-photobooth-rust.vercel.app/.well-known/apple-app-site-association`
(Content-Type application/json, no redirect):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<TEAMID>.com.servify.Photobooth-ai"],
        "components": [
          { "/": "/e/*" },
          { "/": "/v/*" }
        ]
      }
    ]
  }
}
```

Replace `<TEAMID>` with the real Apple Team ID (human-owned). When the
domain moves off vercel.app to boothify.app, update BOTH the entitlement
and the AASA host.
