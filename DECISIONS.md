# DECISIONS

Architectural / scope decisions taken autonomously during the build run that
weren't already pinned in the executive prompt. The prompt's "DECYZJE
ARCHITEKTONICZNE" section is the source of truth — anything here is *in
addition to* those, not a contradiction.

---

## M1 — Stabilization safe-area indicator

Chose **corner-bracket overlay** (~10% inset) over a full inner ring or a
cropped preview. Reasoning:

- A full ring competes visually with the guest in frame and reads as a UI
  bug to anyone who hasn't been briefed.
- Cropping the preview itself would solve the WYSIWYG problem but loses
  peripheral info the operator may want to see (e.g. someone walking into
  shot from the side). Brackets keep the full sensor view while marking
  the safe area.
- Brackets are how cinema viewfinders show action-safe / title-safe
  zones; operators with any prior video gear background read it instantly.

No fallback chain in code for `.cinematicExtended → .cinematic → .standard`
— AVFoundation silently downgrades to the closest supported mode when you
just set `preferredVideoStabilizationMode`. Adding our own iteration would
duplicate that and lock us out of future improvements (e.g. iOS 27's
hypothetical `.cinematicProMax`).
