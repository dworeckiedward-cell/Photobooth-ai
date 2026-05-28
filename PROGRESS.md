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
Status: ✅ done

- `Booth360RecordingView` bottom controls reorganized to a 3-button row:
  **Music ← REC → Presets**. All overlay buttons; the screen remains
  fullscreen camera preview with no scrolling required mid-event.
- Music: `fileImporter` (audio types) — DRM-safe local files only, no
  Apple Music. Picked file is copied into
  `Documents/events/<eventId>/audio/<filename>` (security-scoped resource
  handled). New `AI360Settings.soundtrackRelativePath` field persists the
  selection; existing `soundtrackName` updated for display.
- Presets: new `QuickPresetsSheet` (`.medium` detent) with three baked
  presets (Quick 4s · 720p / Standard 6s · 1080p · slow-mo / Epic 10s ·
  1080p · slow-mo) plus a "All 360 settings…" jump to the full
  AI360SettingsView.
- `Booth360ResultView` migrated from `ScrollView` to fixed vertical layout
  — preview fills available space, metadata chips stack tightly,
  action grid + secondary actions pin to the bottom. No scroll needed.

Build: ✅ green.

## M5 — Twilio per-user
Status: ✅ done

- `KeychainStore` extended with `saveTwilioCredentials` / `loadTwilioCredentials`
  / `clearTwilioCredentials`. Service: `com.servify.Photobooth-ai`, account
  `boothify.twilio`. Accessibility `.afterFirstUnlock`.
- New `TwilioCredentials` struct supports BOTH legacy Account SID + Auth
  Token AND recommended API Key SID + Secret (`kind: CredentialKind`).
- New `TwilioClient` (Swift, direct REST, no SDK):
  - Basic Auth via base64(`authSid:authSecret`).
  - `sendSMS(to:body:using:fromOverride:)` POSTs form-encoded body to
    `https://api.twilio.com/2010-04-01/Accounts/<sid>/Messages.json`.
  - Decodes Twilio's error envelope; surfaces `TwilioError.twilio(code,
    message, moreInfo)` so the wizard shows actionable messages.
- `AI360Settings.soundtrackRelativePath` exists (added in M4) — separate
  from M5 but used by the recording flow.
- New `EmailSMSSettings.smsFromOverride: String` for per-event From-number
  override (e.g. when an operator runs two events from two different numbers).
- New `TwilioOnboardingSheet` (large detent) — 3-field form, segmented
  API Key / Account Token picker, **Save credentials**, **Send test SMS**,
  **Email me the setup steps** (uses `mailto:` so no MFMailCompose dance),
  **Disconnect** option.
- `EmailSMSSettingsView` gains a Twilio status row (Connected / Not
  connected) with "Connect / Manage" button + per-event From override.
- `ResultView.SMSSheet` now routes through `TwilioClient` when the operator
  has connected Twilio; falls back to the existing backend
  `BoothifyAPI.sendSMS` path otherwise. Renders `{{link}}` / `{{eventName}}`
  tokens client-side so guest sees the same message regardless of path.

Build: ✅ green.

## M6 — FFmpeg pipeline + timeline editor
Status: ⚠️ partial — data layer + filter chain builder + UI editor done; binary swap is the remaining 10-line change

### Done
- `CaptureSegment` (duration, speed, reverse, rendered duration computed)
  + `CaptureTemplate` (name, segments, raw/rendered duration computed)
  in `EventSettings.swift`.
- `AI360Settings.templates: [CaptureTemplate]` +
  `activeTemplateId: UUID?` + computed `effectiveSegments` that falls
  back to a one-segment template synthesised from legacy `clipSpeed` /
  `clipDirection`. **No migration needed** — old persisted settings
  decode + run unchanged.
- `CaptureTemplate.defaultProduction` — the sprint-1 "Patryk-approved"
  preset (3s @1.25× + 3s @0.75× + 3s @2× reversed). Loaded on first open.
- New `Booth360FFmpegRenderClient` (`Booth360FFmpegRenderClient.swift`).
  Builds the actual `filter_complex` string from `effectiveSegments`:
  ```
  [0:v]trim=0:3,setpts=PTS/1.25[v0];
  [0:v]trim=3:6,setpts=PTS/0.75[v1];
  [0:v]trim=6:9,setpts=PTS/2.000,reverse[v2];
  [v0][v1][v2]concat=n=3:v=1:a=0[outv]
  ```
  + full ffmpeg argv builder. Speed clamped 0.1×–4×, duration 0.1s–60s.
- New `CaptureTimelineEditor` view — segment list with per-row sliders
  (duration, speed, reverse toggle), add/remove/reorder, "Load default
  preset", "Match recording duration to template" button (syncs
  `recordingDurationSeconds` with raw needed). Auto-hydrates the default
  preset on first open.
- `AI360SettingsView` gains a "Capture timeline" NavigationLink with
  live segment count + raw/rendered preview in the row subtitle.
- Result preview still uses real `finalVideoURL` (from M0 passthrough)
  via the `VideoPreviewPlayer` introduced in M0 — once FFmpeg lands and
  populates the transcoded path, the same player picks it up.

### Stubbed
- **Render client doesn't actually run FFmpeg.** Official ffmpeg-kit-ios
  was retired by its maintainer and SPM-adding a community fork from CLI
  is fragile. `Booth360FFmpegRenderClient.runPipeline` builds and logs
  the full command, then hands off to `Booth360PassthroughRenderClient`
  so the Processing UI still completes with the raw recording as final.
- `Booth360ProcessingView` is still wired to `Booth360APIRenderClient`
  (which falls through to passthrough). Once FFmpeg binaries land,
  re-wire to `Booth360FFmpegRenderClient` (single-line change). See
  `TODO-HUMAN.md` → "M6 — FFmpeg binary".
- Audio in the rendered output: deferred. v1 ships `-an` because
  speed-ramp + reverse audio with `atempo` is fiddly and the time-budget
  for this run didn't allow tuning. Soundtrack from M4 will be muxed in
  cleanly with a separate `-i` input + `-c:a aac -shortest` once FFmpeg
  is real.

Build: ✅ green.

---

# Second run (2026-05-28) — domknięcie z calla

## IM3 — Onboarding quiz
Status: ✅ done (local persistence; backend sync optional later)

- New `OnboardingQuiz.swift` — 4-step skippable sheet:
  1. **Event category** — Wedding / Corporate / Birthday / Club / Other.
  2. **Primary mode** — AI Photobooth / 360 AI Booth / Both.
  3. **Branding** — Client logo / Event-name watermark / None.
  4. **360 montage length** — Quick 4s / Standard 9s / Epic 15s.
- Skip available at every step (toolbar button); progress dots show
  position. Animated transitions, haptics on select.
- Persistence: `OnboardingStore` (UserDefaults). Two flags —
  `hasCompleted` (gate) and `lastAnswers` (Codable answers blob).
  `OnboardingStore.reset()` for test/dev.
- `RootView` presents sheet via `.task` 350ms after the navigation stack
  mounts when `!hasCompleted && isAuthenticated`. `interactiveDismissDisabled(false)`
  so swipe-down also counts as skip.
- **Answers actually do something:** `AppState.createEvent(name:)` now
  reads `OnboardingStore.lastAnswers` and seeds the new event's
  `EventSettings` accordingly — `preferredTemplateRawDuration` →
  `AI360Settings.recordingDurationSeconds`, branding choice →
  `BrandOverlaySettings.enabled / logoSource / overlayText`. Operator's
  stated preferences take effect on their very first event without
  digging through settings.

Build: ✅ green.

## IM2 — Cloud status panel
Status: ✅ done (iOS), ⚠️ backend endpoint pending

- New `EventCloudStatus` model (queued / uploading / done / sent) — Codable
  for the future `/api/events/{slug}/status` wire format.
- `BoothifyAPI.eventStatus(slug:)` added.
- `AppState.cloudStatus(for:)` always-populated reader + async
  `refreshCloudStatus(for:)` that tries backend first, falls back to a
  local rollup built from `Booth360Job` cache + `Event.completedPhotos`.
  Sent counter stays 0 locally (no delivery log).
- New `CloudStatusPanel` SwiftUI view — 4 animated counters
  (`contentTransition(.numericText())`), tap-to-refresh spinner. Mounted
  in `Booth360EventHubView` AND `EventHubView`, between primary card
  and recent items. Auto-refreshes on appear (`task(id: eventId)`).
- Backend doesn't crash the panel when 404 — local snapshot keeps it
  populated. Bumped to TODO-HUMAN.

Build: ✅ green.

## IM1 — QR + AirDrop
Status: ✅ done

- New `QRGenerator.swift` — CoreImage QR generator (`CIFilter.qrCodeGenerator`),
  correctionLevel `H` (30% damage tolerance), nearest-neighbour scaling.
  Reusable SwiftUI `QRCodeView` with white background and graceful "raw
  URL" fallback when encoding refuses.
- `Booth360ResultView` action grid expanded from 3 → 5 tiles:
  **Share (native ShareLink)** · **QR** · **Copy** · **Save** · **New**.
  Share uses SwiftUI `ShareLink(item:)` so AirDrop, Messages, Mail,
  WhatsApp etc. all appear without us re-implementing each one.
- New `Booth360QRSheet` (medium + large detents, ultraThin material) —
  big code, URL printed below, "Copy link" fallback.
- **Save-to-Photos re-enabled** for 360 — now that IM0 produces a real
  `finalVideoURL` we hook `UISaveVideoAtPathToSavedPhotosAlbum`. Toast on
  top of the fixed layout reports success.
- Photo `ResultView` action row gets a 5th button: native ShareLink
  ("AirDrop") sitting alongside SMS / WhatsApp / Email / QR Code. The
  existing in-app `QRSheet` already covered QR; this just adds the system
  share sheet.

Build: ✅ green.

## IM0 — Ożywienie FFmpeg
Status: ✅ done

- SPM dep `tylerjonesio/ffmpeg-kit-spm` dodany przez edycję `project.pbxproj`.
  Pin na commit `6053b0e4f8607314ff5e14e0b18fc250c0f87c9b` (HEAD `main`,
  tagi tego forku są nie-semverowe — `min.v5.1.2.6`). Wybór commit-pin
  zamiast tag-range opisany w `DECISIONS.md`.
- Produkt `FFmpeg-Kit` (wrapper re-exportujący `ffmpegkit` module).
- `Booth360FFmpegRenderClient.runPipeline` przepisany ze stubu na realny
  `FFmpegKit.executeAsync(cmd) { session in … }` z `ReturnCode.isSuccess`
  walidacją.
- Enkoder: `h264_videotoolbox` (hardware, brak GPL contamination, szybszy
  na iPhone 12/13 niż `libx264`). Pixel format `yuv420p`, `+faststart`.
- Audio: opcjonalny soundtrack z M4 (`-i music.m4a -shortest -c:a aac_at
  -b:a 128k`). Brak audio z segmentów (speed-ramp `atempo` fiddly —
  decyzja z 1. runu utrzymana).
- Progress: `FFmpegKitConfig.enableStatisticsCallback` mapuje
  `Statistics.getTime()` (ms) na `Booth360Job.progress` (0…0.95).
  Callback hoppa do MainActor przed upsertem.
- Fallback: jak `ReturnCode` non-success lub plik nie powstał →
  `errorMessage = "Montage failed — saved the raw recording instead."`
  + delegacja do `Booth360PassthroughRenderClient`. **Nigdy nie crashuje
  podczas eventu.**
- `Booth360ProcessingView.task` re-wired na `Booth360FFmpegRenderClient.shared`.
- Logo overlay (M7) ożywa automatycznie — gdy `BrandOverlaySettings.enabled`
  jest true i operator wgrał logo, filter chain dorzuca `-i logo.png` +
  `overlay=...`. Photo flow bake niezmieniony (M7).

**Rozmiar appki:** Debug Simulator build = 72 MB (universal arm64+x86_64,
nie-stripped). FFmpeg frameworks ~29 MB total: libavcodec 14MB,
libavformat 7MB, libavfilter 5MB, libavutil 932K, ffmpegkit 1.2MB.
Release build na realnym device będzie znacznie mniejszy po strip + arm64-only.

Build: ✅ green (zero warnings).

## M7 — Logo overlay picker + bake
Status: ✅ done (photo bake live, video bake hooked into M6 chain)

- `BrandOverlaySettings.customLogoRelativePath: String?` for the on-disk
  PNG path. Persists per event.
- `BrandOverlayLayer` now accepts an optional `eventId` and resolves the
  uploaded PNG from `Documents/events/<eventId>/<relative>` when
  `logoSource == .uploaded`. Falls back to the bundled sample if the file
  is missing or unreadable.
- Static helpers `BrandOverlayLayer.loadUploadedLogo(eventId:relative:)`
  and `BrandOverlayLayer.uploadedLogoURL(eventId:settings:)` — the latter
  is what `Booth360FFmpegRenderClient` uses as `-i` input.
- `BrandOverlaySettingsView` Upload row replaced with a real `PhotosPicker`
  (images, compatible encoding). Image is re-encoded to PNG (so we keep
  alpha) and saved to `Documents/events/<eventId>/logo.png`. Shows status
  ("Logo saved", relative path, errors) + Remove button.
- `BrandOverlayPreviewCard` takes optional `eventId` so the live preview
  in settings shows the uploaded logo.
- `Booth360ResultView` and `Booth360ResultView.AnimatedDemoPreviewCard` +
  `VideoPreviewPlayer` updated to pass `job.eventId` through to
  `BrandOverlayLayer`.
- `ResultView.saveToPhotos` now bakes the brand overlay into the saved
  UIImage via a new `bakeBrandOverlay(into:settings:eventId:)` helper
  (UIGraphicsImageRenderer + per-anchor rect math). Mirrors the SwiftUI
  layer positioning so on-screen preview matches the saved file.
- `Booth360FFmpegRenderClient.buildFilterComplex` extended with optional
  `OverlaySpec` argument. When present, appends:
  ```
  [1:v]format=rgba,colorchannelmixer=aa=<opacity>,scale=min(iw,ih)*<size>:-2[ovl];
  [concatOut][ovl]overlay=<x>:<y>:format=auto[outv]
  ```
  with anchor math for all 5 positions. `buildCommand` adds the second
  `-i <overlay>` input when needed. Reachable as soon as M6 binary lands.

Build: ✅ green.
