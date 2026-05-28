# Quick Wins — UX polish pass (2026-05-28)

Eight low-risk, high-impact visual / interaction polish commits delivered
after the deep audit (`UX_AUDIT.md`). Each is its own commit, so the
batch can be cherry-picked or partially reverted without entangling
unrelated work. No business logic changed; build green after every one.

---

## QW1 — `monospacedDigit()` on render % counter
**Commit:** `b7c78d5`
**File:** `Booth360ProcessingView.swift:118`
**Why:** 40pt rounded percent counter shifted 1-2pt every tick during
the 10s render because proportional digits have different widths.
Operator stares at it the whole time — visible jitter reads as "janky".
**Before:** `.font(.system(size: 40, weight: .bold, design: .rounded))`
**After:** same + `.monospacedDigit()`
**Audit ref:** TOP 10 #1.

---

## QW2 — Semantic `Theme.error/warning/success` tokens
**Commit:** `77efd15`
**File:** `Theme.swift` (+ 5 call-site files)
**Why:** `.red.opacity(0.85)` was hardcoded in 6 places (Booth360Landing,
Photobooth landing, Gallery, SettingsDetailViews, SettingsMVPViews×2).
Each was a private "error red" — no single source of truth for tweaking
contrast or dark-mode behavior.
**Before:** raw `.red.opacity(0.85)` strewn across views.
**After:** new `BoothifyTheme.error` (tuned to ~4.5:1 contrast on bg,
WCAG AA borderline), `.warning` (alias to amber, semantically reserved),
`.success` (alias to emerald). All callsites swapped.
**Audit ref:** TOP 10 #2.

---

## QW3 — Respect Reduce Motion on photo ResultView reveal
**Commit:** `8cce91c`
**File:** `ResultView.swift`
**Why:** iOS Accessibility → Motion → Reduce Motion is an HIG contract;
ignoring it can flag App Review and is straight-up rude to motion-
sensitive users. The 0.7s reveal + glow pulse on a freshly generated
photo was the most visible offender.
**Before:** unconditional 0.7s easeOut + glow pulse via two timed
`withAnimation` calls.
**After:** `@Environment(\.accessibilityReduceMotion)` check;
short-circuit to final values when ON. The photo just appears, no flash.
**Audit ref:** TOP 10 #3. (Onboarding springs + processing ring still
ignore Reduce Motion — bundled in STRATEGIC_PROPOSALS motion-system pass.)

---

## QW4 — `VideoPreviewPlayer` starts muted
**Commit:** `4c97cba`
**File:** `Booth360ResultView.swift` (`VideoPreviewPlayer.setup`)
**Why:** The 360 result auto-plays the moment the operator opens it.
With `isMuted = false`, freshly-recorded audio blares out at full volume
— survivable at a noisy nightclub, embarrassing during a quiet wedding
ceremony moment.
**Before:** `p.isMuted = false`
**After:** `p.isMuted = true`. Native AVPlayer controls let the user
unmute when they actually want sound.
**Audit ref:** TOP 10 #8.

---

## QW5 — Professional loading microcopy
**Commit:** `8b9e23c`
**File:** `ResultView.swift`
**Why:** "Working some magic" / "Mixing pixels with stardust…" /
"Convincing the photons…" reads like a consumer toy. Boothify is
operator-pro tooling; Patryk holds the iPad in front of paying clients.
Halide / Linear voice: confident, brief, never cute.
**Before:** headline "Working some magic"; 6 cutesy rotating sub-lines.
**After:** headline "Generating photo"; 5 functional sub-lines
("Reading the scene…", "Composing your portrait…", "Applying the
style…", "Refining the details…", "Almost there…").
**Audit ref:** TOP 10 #10.

---

## QW6 — VoiceOver labels on 360 job thumbs + slideshow counter
**Commit:** `b7929de`
**Files:** `Booth360EventHubView.swift`, `SlideshowView.swift`
**Why:** A12 (accessibility) was the second-weakest dimension in the
audit. Two surfaces were the highest-visibility silent buttons:
- 360 job thumbnails on Event Hub: VoiceOver said only "Button".
  Now labeled with status + a hint about what tapping does.
- Slideshow position pill: VO read just "1 / 12". Now reads
  "Slide 1 of 12", plus `.monospacedDigit()` so the count doesn't
  jiggle width as it ticks.
**Before:** unlabeled buttons + proportional-width counter.
**After:** explicit `accessibilityLabel` + `accessibilityHint` on thumbs;
monospaced counter with full position label.

---

## QW7 — Success haptic on cloud upload completion
**Commits:** `8cbea98` + `440ba7d` (UIKit import fixup)
**File:** `Booth360CloudUploader.swift`
**Why:** A6 (haptics). The uploader's success branch flipped status
silently — operator who'd moved on to the next guest had no signal that
the previous take had reached the cloud and was shareable.
**Before:** silent on `.uploaded`.
**After:** `Haptics.notify(.success)` after status flip. (No haptic on
`.failed` — the red `uploadStatusBar` already screams visually; double-
feedback would feel nagging.)

---

## QW8 — Semantic fonts on CloudStatusPanel counters
**Commit:** `4b6a452`
**File:** `CloudStatusPanel.swift`
**Why:** A1 (typography) + A12. Icon + uppercase label were both
`.system(size: 10)` — hardcoded sizes don't respect Dynamic Type, so
operators with Accessibility large text on saw the counters scale while
the labels stayed pinned at 10pt.
**Before:** `.system(size: 10, weight: .bold|.medium)`
**After:** `.caption2.weight(.bold|.medium)` — count was already
`.title3.monospacedDigit()` and stays.

---

## What's NOT in this batch (deliberately)

Audit issues that need >30 min or carry regression risk landed in
`STRATEGIC_PROPOSALS.md` instead. Specifically:

- **Offline indicator** (TOP 10 #5) — needs new banner component +
  reachability plumbing. M effort.
- **Thermal state hook** (TOP 10 #6) — needs `ProcessInfo` observer +
  UI surface. M effort.
- **Crash-restart context restore** (TOP 10 #7) — touches `RootView` +
  `AppState` route persistence. M effort, regression-sensitive.
- **Web viewer `navigator.share()` + footer CTA** (TOP 10 #9) — backend
  repo touch + has marketing implications worth a real review. S effort
  but cross-repo.
- **Full Dynamic Type pass** (TOP 10 #4) — Login, ModeSelection,
  EventHub, Booth360EventHub, Photobooth/360 landings, Gallery: many
  files, many lines, each individually trivial. Better as one sweeping
  PR than 7 micro-commits.
- **Reduce Motion on the rest of the app** — onboarding springs,
  StarField (web), processing ring. Bundle with motion-system spec.
