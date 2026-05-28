# PROGRESS — Loomabub-killer build run

Execution log for the multi-milestone implementation run requested on 2026-05-28.
Each milestone gets ✅ done / ⚠️ partial / ⛔ blocked + a short note.

---

## M0 — Real video recording foundation
Status: ✅ done

- `CameraController` rebuilt as dual-mode (`.photo` / `.video`). Photo flow
  untouched. Video mode adds `AVCaptureMovieFileOutput` + audio input
  (`AVCaptureDevice.default(for: .audio)`) at session preset `.hd1920x1080`
  (fallback `.high`). [CameraScreen.swift:407-560]
- `startRecording(to:)` / `stopRecording()` async API on the controller.
  `MovieCaptureDelegate` handles the "success-as-error"
  (`AVErrorRecordingSuccessfullyFinishedKey`) quirk.
- `NSMicrophoneUsageDescription` added to Debug + Release build settings
  in `project.pbxproj`. Camera + photo library descriptions updated to
  mention 360 video.
- `Booth360RecordingView` now requests camera + mic permissions in tandem,
  starts the session in `.video` mode, writes the .mov to
  `Documents/events/<eventId>/raw_<unix>.mov`, and hands the URL off in
  `Booth360Job.rawVideoLocalURL`.
- `Booth360PassthroughRenderClient` (new, in `Booth360.swift`) replaces
  `MockBooth360RenderClient` as the wired client in
  `Booth360ProcessingView`. Surfaces the real recording as `finalVideoURL`,
  walks the same 6-step UI, falls back to mock if no file was written
  (simulator).
- `Booth360ResultView` now renders the real recording via a new
  `VideoPreviewPlayer` (auto-play + loop) when `finalVideoURL` exists;
  animated placeholder is the fallback.

**Photo flow:** untouched — still uses `start(mode: .photo)` (default).
Build: ✅ green on iOS Simulator (arm64 + x86_64), zero warnings.

## M1 — Native video stabilization
Status: _pending_

## M2 — Apple Sign In gate ON + account UI hardening
Status: _pending_

## M3 — Cloud sync for 360 jobs (iOS side)
Status: _pending_

## M4 — Recording + Result UI refactor
Status: _pending_

## M5 — Twilio per-user
Status: _pending_

## M6 — FFmpeg pipeline + timeline editor
Status: _pending_

## M7 — Logo overlay picker + bake
Status: _pending_
