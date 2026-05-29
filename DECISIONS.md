# DECISIONS — iOS RUN B

(Decisions taken autonomously this run, in addition to the locked-in
DECYZJE from the executive prompt.)

---

## BM0 — Cloud upload as separate phase from render

The FFmpeg render and the cloud upload are intentionally **two phases**,
not one chained call. Render writes a local mp4 + marks status
`.completed`; upload runs after as a background `Task` via
`Booth360CloudUploader.enqueue`.

Why split:
- Operator can navigate to the Result screen / start the next guest's
  recording the instant render finishes. Upload runs invisibly in the
  background.
- Failed upload doesn't undo a successful render — the local file is
  still there to share via AirDrop / Save to Photos, and the queue
  retries the cloud step independently.
- BM1's persistent queue lives entirely in the upload phase; nothing
  about render needs to know about it.

## BM0 — `clientJobId` lifecycle

Generated **once** at `Booth360Job.init` time and reused unchanged on
every retry attempt. The backend's idempotency contract (AM1: lookup
via `metadata->>client_job_id`) means re-running sign → PUT → confirm
with the same id always lands on the same row + storage object.

That's why `Booth360Job.clientJobId` is a `var` only for Codable
synthesis convenience — semantically it's write-once.

## BM0 — Mock share URL kept as optimistic placeholder

Right after render, `publicShareURL` is set to a fake `boothify.app/v/...`
URL. The real one only arrives after `confirm`. We keep the mock so that
the Result screen's QR / Copy Link / ShareLink buttons render with
*something* even if the upload hasn't completed yet — the displayed link
would 404 if scanned immediately, but the UI doesn't crash. Once upload
completes the URL silently swaps to the real backend-minted one.

If we hard-required the real URL upfront the operator would see a
broken Result screen for 5-30s while the upload runs. Bad UX during a
live event.

---

# Pre-Event Omnibus — RUN A — 2026-05-29

(Autonomous decisions taken on top of the executive prompt's
locked-in `DECYZJE TWARDE`.)

## RA0 — Gate `cloudReady`, don't hide buttons

Share/QR/SMS/Copy stay visible but disabled (with a subdued look) while
`cloudUploadStatus != .uploaded`. Hiding them entirely would shift the
layout under the operator's thumb mid-tap; disabling preserves muscle
memory and signals "almost there" rather than "feature missing." Local
actions (Save to Photos, New) remain enabled — they don't depend on
the cloud round-trip.

## RA1 — Thermal multiplier curve + 30s debounce

Picked `nominal/fair → 1.0`, `serious → 0.7`, `critical → 0.5`. These
are educated guesses, not measured — flagged in `OMNIBUS_REPORT.md`
follow-ups for real-event calibration. The `isStable(debounce: 30)`
gate prevents thrash: a brief spike to `.serious` between renders
won't yank the next render's bitrate if the device cools back down
inside the debounce window.

`ThermalMonitor` is a `@MainActor @Observable` singleton with no
deinit observer cleanup — it lives the lifetime of the app, so the
notification subscription leaks nothing in practice and Swift 6's
MainActor-isolated `deinit` rules made the cleanup fight the compiler.

## RA2 — Restore to Event Hub, never directly into Recording

`CrashRestoreManager` stashes `lastActiveEventId` when the user enters
either EventHub (photo) or Booth360EventHub. On bootstrap we push the
hub onto the navigation stack — never the Recording screen directly,
even if that was the last visible screen. Restoring straight into
Recording would re-arm the camera + mic on app launch, which is
surprising and potentially privacy-hostile after a crash. Hub is the
safe "you're back where you were" landmark.

Landing screens (`PhotoboothLandingView`, `Booth360LandingView`) clear
the stash on `.task` — backing out of an event is an explicit signal
that the operator does NOT want restore-on-launch.

## RA3 — Sentry config: DSN from Info.plist, PII off, 10% traces

- DSN read from `Bundle.main.object(forInfoDictionaryKey:
  "BOOTHIFY_SENTRY_DSN")`. Keeps it out of the repo and out of source;
  set via Xcode scheme env or Info.plist user-defined key.
- `sendDefaultPii = false`. The only user identifier we attach is the
  Supabase UUID (`SentryClient.setUser(id:)`) — no auto-collected
  emails / IPs / device names. Aligns with the privacy posture set in
  AM2 (nullable email column for private-relay users).
- `tracesSampleRate = 0.1`. 10% performance sampling is enough to spot
  systemic slowness without burning quota on a live event with one
  operator.
- Release name `boothify-ios@<version>+<build>` so dSYM symbolication
  has a stable key.

Breadcrumbs added to: app launch, render start/end, upload
sign/PUT/confirm, auth state changes. Non-fatal `captureMessage` on
render-fallback (passthrough kicked in) so we can see how often the
FFmpeg path degrades without crashing.

## RA4 — Minimal HUD, not full P2 redesign

`StatusOverlay` is a single pill below the safe area that surfaces
only the **most-severe** of: offline / hot / battery < 20% / pending
uploads, with a `+N` badge for other active warnings. Invisible when
nothing is wrong. The full P2 from `STRATEGIC_PROPOSALS.md`
(expand-on-tap, drill-down per warning) is intentionally deferred —
audit guidance was "wait for real-event signal before designing the
expanded UX." Battery monitoring enabled in `onAppear` (default-off on
iOS); `accessibilityReduceMotion` gates the slide transition.

## RA5 — Four motion tokens, opinionated curves

```swift
quickTap   = .spring(response: 0.25, dampingFraction: 0.85)  // taps, badges
smoothFlow = .spring(response: 0.45, dampingFraction: 0.85)  // sheets, HUD
bouncy     = .spring(response: 0.55, dampingFraction: 0.65)  // success moments
gentle     = .easeInOut(duration: 0.3)                       // progress, state crossfade
```

Four was the sweet spot — three felt too coarse (success-flash and
sheet-slide want different energy), five+ invites the same drift the
tokens are supposed to prevent. `BoothifyMotion.animate(_:reduceMotion:_:)`
helper centralizes the Reduce Motion check so callsites don't each
reimplement it.

**Files swept (7):** `Booth360ResultView` (copy flash + save toast →
`bouncy`), `Booth360RecordingView` (countdown → `quickTap`),
`Booth360ProcessingView` (step/progress → `gentle`),
`Booth360EventHubView` (copy flash → `bouncy+quickTap`),
`EventHubView` (copy flash → `bouncy+quickTap`), `StatusOverlay`
(slide → `smoothFlow`).

Sweep was deliberately **targeted, not exhaustive** — main flows only,
per the prompt's "quality over coverage" constraint. Remaining
animation callsites still use ad-hoc curves; they're listed for a
follow-up sweep but not blocking.

## RA6 — Type scale backed by semantic fonts, Dynamic Type from day one

```swift
display       = .system(.largeTitle).bold
displayMedium = .system(.title).bold
title         = .system(.title2).semibold
body          = .system(.body)
bodyEmphasis  = .system(.body).semibold
caption       = .system(.caption)
mono          = .system(.body).semibold.monospacedDigit()
```

Every token is backed by Apple's semantic font (`.largeTitle`,
`.title`, `.body`, etc.) — Dynamic Type scaling is automatic, no
opt-in. Avoiding `.system(size: N)` is the rule going forward;
operators with Accessibility large-text on otherwise see the rest of
the UI grow while one hardcoded label stays pinned.

**Files swept (4):** `EventHubView` + `Booth360EventHubView` headers
(`.system(size: 26)` → `BoothifyType.title`); `PhotoboothLandingView` +
`Booth360LandingView` 'Start a new…' titles (`.system(size: 28)` →
`BoothifyType.displayMedium`); `Booth360LandingView` BETA badge
(`.system(size: 9)` → `.caption2.weight(.bold)`).

**Intentional holdouts** (single-callsite, deliberate):
- 220pt rounded countdown numerals in `Booth360RecordingView` — one-off
  display element; not type-system territory.
- Apple-Pay-style hero brand wordmarks — brand, not type.

Remaining `.system(size:)` callsites (~12 files, mostly badges + decorative
numerals) are flagged for the next sweep — not blocking the event.

## RA7 — Strip flags on Release only

`STRIP_INSTALLED_PRODUCT`, `STRIP_STYLE = all`, `COPY_PHASE_STRIP`,
`DEAD_CODE_STRIPPING` applied to the **Release** config only. Debug
keeps full symbols so LLDB + Sentry breakpoints still work locally.
Actual IPA size measurement requires an Xcode Archive — flagged in
`TODO-HUMAN.md`.
