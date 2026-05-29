# Pre-Event Omnibus — RUN A (iOS)

Closes two layers before the first real event with Patryk:

1. **Event Survival** (RA0–RA4, RA7) — thermal, crash-restart, error
   reporting, status HUD, mock-URL gate, release build hardening.
   "Things that will bite us live."
2. **Design System Foundation** (RA5–RA6) — motion + typography tokens
   + targeted sweeps. "Things that make the next polish ROI compounding
   instead of ad-hoc."

Build green after every commit; nothing in the protected core (upload /
auth / render / cloud sync / photo flow / 8 QWs from prior run) was
touched.

| # | Milestone | Status | Commit |
|---|-----------|--------|--------|
| RA0 | Mock Share URL gate | ✅ | `1c27ec0` |
| RA1 | Thermal monitor + auto-degrade bitrate | ✅ | `cee3b29` |
| RA2 | Crash-restart context | ✅ | `621f846` |
| RA3 | Sentry SDK + breadcrumbs in major flows | ✅ | `b46340b` |
| RA4 | Unified Status HUD overlay | ✅ | `0bb0396` |
| RA5 | MotionTokens system + 7-file sweep | ✅ | `bddfd17` |
| RA6 | Typography token system + 4-file sweep | ✅ | `218792c` |
| RA7 | Release build strip / dead-code | ✅ | `3e903c1` |

---

## What changed for the operator (felt impact)

- **Cloud-dependent Share / SMS / QR / Copy buttons stay disabled until
  upload confirms.** Guest never gets a 404 link.
- **Render bitrate auto-drops when device is hot.** 4-hour event no
  longer ends in silent thermal throttling — operator now sees a hot
  pill in the HUD and the render quality degrades intentionally.
- **App restarts straight into the last event hub** after a crash, not
  the event picker. 3-tap drill-back gone.
- **Operator HUD pill** surfaces offline / hot / low battery / pending
  uploads. Only renders chrome when something's wrong; invisible
  otherwise.
- **Animations feel consistent across the main flows** — same spring
  curve on every copy-link flash, same gentle ease on every progress
  bar. Subtle but cumulative.

## What changed for us (operations impact)

- **Sentry captures crashes + non-fatal errors with user-id breadcrumbs.**
  Next time Patryk says "appka crashowała 3 razy", we have stack traces
  + the user-actions timeline.
- **Release build size unchanged on Simulator (72 MB universal); strip
  flags applied for the real-device IPA.** Exact .ipa size requires
  Xcode Archive — see TODO-HUMAN.md.

## What's NOT in this run (deliberately)

Listed in the prompt's "NIE ROBIĆ" section + repeated in `DECISIONS.md`:

- **Operator dashboard webowy** — awaits event feedback.
- **Background URLSession upload queue** — awaits skala evidence.
- **Full operator HUD redesign (P2)** — RA4 is the minimal version;
  expand-on-tap + drill-down decisions need real-event signal.
- **Color token system pełny** — restraint per audit guidance; only
  `Theme.error / .warning / .success` from QW2.
- **Photo flow changes / new 360 features** — protected scope.

## Build sanity

- Build: ✅ green on Debug + Release Simulator universal (arm64 + x86_64).
- Photo flow: unchanged, still works.
- Auth gate: production-on per AppConfig; Debug `BOOTHIFY_BYPASS_AUTH=1`
  env bypass (IM4) preserved.
- 8 quick wins from prior run (QW1-QW8) all still in place — no regressions.

---

## Open follow-ups (for after-event review)

- Full Dynamic Type sweep of remaining `.system(size:)` callsites (mostly
  badges + decorative numerals; ~12 files left).
- Result screen gesture-driven redesign (P3 from STRATEGIC_PROPOSALS).
- Status HUD expand-on-tap (current shows most-severe + "+N" badge).
- Real-event measurement of thermal degradation thresholds — current
  30%/50% bitrate drops are educated guesses, not measured.

See `PROGRESS.md` for the full chronology and `STRATEGIC_PROPOSALS.md`
for larger moves still awaiting greenlight.
