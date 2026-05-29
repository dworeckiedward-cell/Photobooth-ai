# TODO — manual setup for RUN B (iOS)

Actions Eduardo needs to take to test the new upload pipeline end-to-end.
The iOS code is in place; these unblock the realistic flow.

---

## 🚨 CRITICAL — REVERT BEFORE APP STORE SUBMISSION

**Apple Sign In gate is currently DISABLED for pre-event testing.**

- File: `Photobooth-ai/AppConfig.swift`, line ~24 (inside `#if DEBUG`)
- Current behavior: Debug builds skip `LoginView`; Release builds still
  require Apple Sign In (unchanged).
- Commit reference: `d610b6b` — `test(auth): temporarily disable Apple
  Sign In gate for testing`

**Revert (two options):**

1. **Cleanest** — `git revert d610b6b` restores the IM4 opt-in env-var
   semantics (gate ON by default in Debug, `BOOTHIFY_BYPASS_AUTH=1`
   flips it OFF).
2. **Surgical** — open `AppConfig.swift`, find the `#if DEBUG` branch,
   change `return false` (the unconditional fallback after the env
   check) to `return true`. Update the doc comment to drop the 🚨
   warning.

**Why this matters:** App Store review will reject if the entitlement
is present (which it is) but the app never actually shows the Apple
Sign In flow. The gate must be ON before TestFlight / submission.

---

## RUN B test prerequisites

Backend must be live first (RUN A → `pnpm supabase db push` + Vercel
redeploy of commit `1076c84` or newer). Once it is:

1. **Point iOS at the right backend.** In Xcode → Edit Scheme → Run →
   Arguments → Environment Variables (or `Info.plist`
   `BOOTHIFY_API_BASE_URL`), set to your prod / staging URL.
   Currently defaults to `http://localhost:3000`.

2. **Real-device test of the direct-upload flow:**
   - Install on iPhone 12+ (FFmpeg needs hardware encoder).
   - Sign in with Apple → confirm session lands (check `AccountSettingsView`).
   - Record a 360 → wait for FFmpeg to finish → wait a few seconds for
     upload.
   - In Xcode's Network tab confirm the file PUT goes to a
     `*.supabase.co` host (NOT your Vercel domain). That's how you
     prove direct upload is bypassing the 4.5 MB cap.
   - Open the SMS share link on a guest phone — video plays.

3. **Resilience test (BM1):**
   - Record a 360.
   - Immediately enable Airplane mode after FFmpeg finishes but before
     upload completes (~3-5s window).
   - Confirm: upload marked `.failed`, "Send again" surfaces in
     Result/Gallery (BM1 UI).
   - Disable Airplane mode → tap Send again → upload succeeds, real
     share URL replaces the mock.
   - Kill + reopen the app while upload is queued → check that on the
     next launch `Booth360UploadQueue.replayPending` re-fires it
     automatically.

4. **SMS counter test (BM2):**
   - After a successful upload, send the link via SMS through the
     in-app TwilioClient.
   - Check the Cloud Status panel — `sent` counter should tick to 1.

---

## Known constraints

- Apple Sign In does NOT work in the simulator for fresh accounts. Use
  a real device signed into iCloud for first login.
- BoothifyAPI.shared.uploadVideoDirect uses a transient URLSession with
  default timeouts (60s request, 300s resource). Larger takes on very
  slow networks may need an iPad on cellular hotspot rather than
  congested venue WiFi.

---

(End of RUN B TODO-HUMAN. See backend repo `ai-photobooth/TODO-HUMAN.md`
for RUN A's deploy block.)

---

# Pre-Event Omnibus — RUN A — 2026-05-29

These items unblock the RA3 (Sentry) + RA7 (release tuning) work.
The iOS code is wired and compiling; these connect it to real-world
infrastructure.

## 1. Sentry project + DSN

The SDK is integrated (`b46340b`) and reads its DSN from
`BOOTHIFY_SENTRY_DSN` in `Info.plist`. Without that key set, Sentry
silently no-ops — safe, but means zero crash reports.

To turn it on:

1. Create a Sentry project at https://sentry.io (Platform: iOS / Cocoa).
2. Copy the DSN (`https://<key>@<org>.ingest.sentry.io/<project>`).
3. In Xcode:
   - Open `Info.plist` → add a new key `BOOTHIFY_SENTRY_DSN` (String) =
     the DSN value, **or**
   - Edit Scheme → Run → Arguments → Environment Variables, add
     `BOOTHIFY_SENTRY_DSN` = DSN (Debug-only; prod still needs the
     Info.plist entry for Release / TestFlight).
4. Build + run → check Sentry dashboard, the "app launched" breadcrumb
   should fire on first foreground.
5. Force a test crash (`fatalError("sentry test")` somewhere temporary)
   to confirm crash capture works end-to-end. Remove the test code.

**Privacy:** `sendDefaultPii = false` is set. The only user identifier
Sentry sees is the Supabase user UUID (set via
`SentryClient.setUser(id:)`). No emails, no IPs, no device names.

## 2. dSYM upload as post-archive Build Phase

Without dSYMs, Sentry crash reports are addresses, not function names —
useless for triage. Sentry's `sentry-cli` automates the upload.

1. Install: `brew install getsentry/tools/sentry-cli`
2. Set env vars (or `~/.sentryclirc`):
   - `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`
3. In Xcode → target `Photobooth-ai` → Build Phases → "+" → New Run
   Script Phase, named "Upload dSYMs to Sentry". Script:
   ```sh
   if which sentry-cli >/dev/null; then
     export SENTRY_LOG_LEVEL=warn
     sentry-cli debug-files upload --include-sources "$DWARF_DSYM_FOLDER_PATH"
   else
     echo "warning: sentry-cli not installed, skipping dSYM upload"
   fi
   ```
4. Run an Archive → check Sentry → Settings → Projects → Debug Files;
   the dSYM for your build should appear.

## 3. App Store archive size measurement

RA7 added strip + dead-code flags to the **Release** config only
(commit `3e903c1`). The 72 MB Simulator universal number in
`OMNIBUS_REPORT.md` is NOT the IPA size — Simulator builds carry both
arm64 + x86_64 + are unstripped. Real shipping IPA strips x86_64 and
all symbols.

To measure:

1. Xcode → Product → Archive (iOS device target, not Simulator).
2. Organizer → Distribute App → App Store Connect → Export.
3. Open the exported `.ipa` (it's a zip) → check size on disk.
4. Expected: **~35-45 MB**. If it's >60 MB, something didn't strip
   correctly — check the Archive's `.xcarchive/Products` for residual
   debug symbols or unused frameworks.

This also gives you the App Thinning report (Organizer → Validate App)
which shows the per-device-variant download sizes.

## 4. Real-event thermal calibration (optional, post-event)

The bitrate multipliers (`.serious → 0.7`, `.critical → 0.5`) in
`ThermalMonitor` are educated guesses, not measured against real
device heat curves. After Patryk's event:

- Pull Sentry breadcrumbs for any `[Render]` lines that include
  `thermal: serious` / `critical`.
- Cross-reference with the operator's recollection of which clips felt
  noticeably degraded vs which were imperceptible.
- Adjust the constants in `ThermalMonitor.bitrateMultiplier` based on
  observed perceived quality at the chosen multipliers.
