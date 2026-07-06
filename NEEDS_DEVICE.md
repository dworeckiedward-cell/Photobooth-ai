# Boothify 360 — NEEDS-DEVICE (cannot be verified in simulator/CI)

## Carried over from pre-pivot state
- Real camera capture (simulator uses placeholder frames).
- 120/240 fps format availability + actual capture quality (Phase 3 Gate B).
- Runtime behavior on a physical iOS 17.x device (target retargeted in Phase 0;
  compile-verified only).

## Phase 0
- Passthrough render output on a real recording (simulator can exercise the
  code path but not a real capture file end-to-end with camera input).

## Phase 1
- Kiosk attract → 360 recording flow on a real device (camera).
- Template-chip apply + kiosk button: sim-verifiable visually, but full guest loop
  (record → process → result) needs camera hardware.
