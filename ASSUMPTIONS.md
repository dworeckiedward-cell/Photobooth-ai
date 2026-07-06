# Boothify 360 — Assumptions (for human audit)

## Phase 0

1. **iPhone 17 Pro simulator is an acceptable gate destination** (scripts/gate.sh).
   The deployment target is 17.0 but no iOS 17 simulator runtime is installed on
   this machine; compile-time availability is verified, runtime on iOS 17 hardware
   is NEEDS-DEVICE.
2. **`EventSettings.default` exists and is the canonical empty state**
   (EventSettings.swift — used by the decoder's per-section fallbacks). Tests
   assume decoding `{}` yielding `.default` is the intended contract, not an
   accident.
3. **Booth360UploadQueue's on-disk manifest surviving test runs is acceptable** —
   tests clean up their own ids (tearDown) rather than resetting the singleton,
   because the file path and `load()` are private.
