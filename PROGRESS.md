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
Status: ✅ done

- `CameraController.configureStabilization()` requests
  `.cinematicExtended` on the movie output's video connection. Applied
  after session commit (connection only exists once movie output is wired)
  and re-applied on `flip()`. AVFoundation silently falls back to the
  closest supported mode for the device, so no manual fallback chain is
  needed in code.
- `StabilizationSafeAreaFrame` overlay (in `Booth360RecordingView`) shows
  four faint corner brackets at the ~10% inset that `.cinematicExtended`
  will crop. Operator now sees exactly what will land in the final file.

Build: ✅ green.

## M2 — Apple Sign In gate ON + account UI hardening
Status: ✅ done

- `AppConfig.authGateEnabled = true` — RootView now shows `LoginView`
  whenever there's no session.
- LoginView requests `[.email, .fullName]` scopes. New `AppleProfileCache`
  (`AppleProfileCache.swift`) persists Apple's first-login `email` +
  `fullName` to UserDefaults so they survive the rest of the app's lifetime
  (Apple ships them ONLY on first authorization, never again).
- `AuthClient.signInWithApple(_:nonce:firstLoginEmail:firstLoginFullName:)`
  forwards those values to the backend on every sign-in (so the backend
  can idempotently backfill them).
- `AuthClient.deleteAccount(accessToken:)` calls `DELETE /api/auth/account`
  (endpoint not deployed yet — graceful fallback in UI signs the user out
  locally + shows a "email support to finish removal" hint).
- `AppState.signOut()` now also clears `AppleProfileCache`.
- `AccountSettingsView` gains: Signed-in identity section (name, email,
  Supabase user id with monospaced display), **Sign out** confirmation,
  **Delete account** confirmation + spinner + graceful error path.

Build: ✅ green.

## M3 — Cloud sync for 360 jobs (iOS side)
Status: ✅ done (iOS), ⚠️ blocked on backend

- New `ShareMode` enum (`.private` default, `.public`) on `Event` +
  `Event.effectiveShareMode` convenience falling back to `.private` when
  the column isn't shipped yet. Backward-compat — older payloads decode.
- New `Booth360JobDTO` wire model in `APIModels.swift`.
- `BoothifyAPI` gains four endpoints (wire format matches photo flow):
  `uploadBooth360Job(rawVideoURL:eventId:settings:)`,
  `getBooth360Job(id:)`, `pollBooth360JobUntilTerminal(id:onUpdate:)`,
  `listEventBooth360Jobs(slug:)`, `updateEventShareMode(slug:shareMode:)`.
- New `Booth360APIRenderClient` (in `Booth360.swift`) — uploads raw .mov,
  polls backend job, streams updates to the local job via `app.upsertJob`.
  Falls back to `Booth360PassthroughRenderClient` on ANY failure (404,
  401, network, simulator-no-camera) so the user never sees a stuck spinner.
- `Booth360ProcessingView` rewired to the API client (single-line change).
- `SharingSettingsView` gains a Share Mode picker at the top of the form
  with optimistic local update + backend PATCH + error display + auto
  no-op in demo mode.

Build: ✅ green. Functional path waits on backend (see TODO-HUMAN.md).

## M4 — Recording + Result UI refactor
Status: _pending_

## M5 — Twilio per-user
Status: _pending_

## M6 — FFmpeg pipeline + timeline editor
Status: _pending_

## M7 — Logo overlay picker + bake
Status: _pending_
