# DECISIONS

Architectural / scope decisions taken autonomously during the build run that
weren't already pinned in the executive prompt. The prompt's "DECYZJE
ARCHITEKTONICZNE" section is the source of truth — anything here is *in
addition to* those, not a contradiction.

---

## IM0 — FFmpeg package pin

Picked `tylerjonesio/ffmpeg-kit-spm` per the prompt. Their tag scheme is
non-semver (`min.v5.1.2.6`, `v5.1`, `v5.1.2`) — Xcode SPM expects strict
SemVer for `upToNextMajorVersion`-style ranges, so resolution failed when
asking for `6.0.0..<7.0.0`. **Resolution:** pin to commit
`6053b0e4f8607314ff5e14e0b18fc250c0f87c9b` (current `main` HEAD at run time).

Trade-off vs. tag range:
- `revision` pin = reproducible, doesn't drift on `pod update`, but you
  need to bump manually when the package ships fixes.
- `branch = "main"` was the alternative — auto-tracks but breaks
  reproducible builds.

When the maintainer starts publishing semver tags, switch the requirement
to `from: "5.1.2"` (their highest semver tag today) and bump from there.

## IM0 — Audio path

Render command's audio handling:
- If operator picked a soundtrack in M4 (`AI360Settings.soundtrackRelativePath`)
  → mux as a separate `-i` input with `-c:a aac_at -b:a 128k -shortest`.
  `aac_at` is Apple's hardware AAC encoder, no extra deps.
- No soundtrack → `-an` (silent). Audio from raw input is dropped on
  purpose — we'd need `atempo` chained for speed-ramp segments, which
  desyncs noticeably at extreme speeds and adds 30-60% to the cmdline
  complexity. Decision from the M6 prompt explicitly allowed this skip.

If a soundtrack is set but the file is missing on disk we silently fall
back to `-an` — never block the render on a missing audio asset.

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
