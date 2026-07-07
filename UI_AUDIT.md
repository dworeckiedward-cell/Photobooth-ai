# Boothify 360 — UI AUDIT (przed polishem; stan v1.0-360-rc1)

Każdy ekran przeczytany w kodzie w całości. Skala: premium / OK / wireframe-tier / broken.

---

## A1. Kiosk Attract — `Photobooth-ai/KioskAttractView.swift` (147 L) — **OK**

- **Hierarchia:** dobra — tytuł eventu + jedno CTA. Ale bohaterem jest ikona
  `camera.aperture` (relikt foto-ery) i **fiolet**, nie marka operatora.
- **Branding operatora:** BRAK — pokazuje tylko nazwę eventu; operatorskie logo
  (brandOverlay, jeśli skonfigurowane) nieużyte. "Powered by Boothify" widoczny
  (footnote/muted — za głośny wg briefu "Boothify niewidzialny albo maleńki").
- **Akcent:** violet (radial + CTA) — w apce 360-only akcent 360 to AMBER;
  attract jest jedynym ekranem gościa na fiolecie → niespójna opowieść barwy.
- **Stany:** brak wariantu "render w toku — za chwilę twoja kolej"
  (AppState.hasActiveRenders istnieje i jest nieużyty przez UI).
- **Ruch:** pulse 1.4 s autoreverse — bez szwu ✓; reduce-motion ✓ (statyczny).
- **Spacing:** literały 28/16 w CTA (poza tokenami) — drobne.
- **Copy/i18n:** fallback tytułu "Photo Booth" niezlokalizowany i foto-erowy.

## A2. Capture + Countdown — `Booth360RecordingView.swift` (719 L) — **OK**

- **Kiosk higiena:** GOŚĆ WIDZI UI OPERATORA — topBar (back+gear), przyciski
  Music/Presets zawsze widoczne. Brief: czysty ekran gościa w kiosku. Brak
  gate'owania na `app.isKiosk`.
- **Countdown:** 220 pt digits ✓, ale bez sygnału "przygotuj się → TERAZ" —
  same cyfry; brak momentu "GO!".
- **i18n (guest-facing, hardkod EN):** "Tap to start a Xs recording",
  "Platform rotating — keep guests centered", storage alert; permission overlay
  (operator-facing — EN dopuszczalny, ale to samo okno widzi gość).
- **Uczciwość ramki:** `StabilizationSafeAreaFrame` (crop-guide) rysuje się
  ZAWSZE — nawet gdy preset = Off (kłamie o cropie, wprost sprzeczne z
  filozofią Phase 6).
- **Raw color:** `.red` dla REC (konwencja, ale poza tokenami).
- **Stany:** consent ✓ (sheet), permission-denied ✓ (dobrze zrobiony overlay z
  Open Settings), storage ✓ (Alert — surowy systemowy, spójny wzorzec byłby
  lepszy, ale Alert jest akceptowalny dla blokera), arming/trigger — machine
  z Phase 8 NIEpodpięta do UI (timer/manual działa przez istniejący countdown).
- **QuickPresetsSheet:** presety operatorskie duration/quality — OK (operator).

## A3. Processing — `Booth360ProcessingView.swift` (323 L) — **OK+**

- **Hierarchia:** ring % + krok + tipy + lista kroków — dobra, "nigdy nie
  wygląda na zawieszone" spełnione (ring + rotujące tipy + krok aktywny).
- **Paleta:** ring `amber→fuchsia→amber` — **fuchsia = legacy "do not use in
  new UI"** (komentarz w Theme). Ambient glow też fuchsia.
- **i18n:** CAŁY ekran EN hardkod (tytuł, 6 tipów, "Done — preparing preview…",
  "Render failed", "Back"); guest-facing → wymaga EN/PL/DE. Step labels z enuma
  (Booth360.swift) — EN.
- **Failed:** raw `.red`, brak **Retry** mimo że raw jest zachowywany na
  failure właśnie po to (klient celowo nie kasuje!); tylko "Back".
- **Kiosk background-render:** przycisk "Next guest" ✓, ale komunikat "wideo
  dokończy się w tle" tylko w accessibilityHint — wizualnie brak.
- **Spacing:** literały 26/24/14/12/10.

## A4. Result + QR — `Booth360ResultView.swift` (817 L) — **OK / jedna sprzeczność**

- **SPRZECZNOŚĆ Z PHASE 7 (deferred-resolve):** `cloudReady = uploadStatus ==
  .uploaded && url != nil` gate'uje QR/SMS/Copy/Share — a cała pointa Phase 7:
  link istnieje OD SIGN (w trakcie uploadu). Gość czeka na upload, którego
  czekać nie musi. Gating to prezentacja — do poluzowania na `publicShareURL
  != nil` (pasek uploadu i tak komunikuje stan).
- **Offline/queued:** upload failed → CZERWONA panika "Upload failed" + retry.
  Gdy przyczyną jest brak sieci, brief każe: spokojne "w kolejce — dostarczy
  się po sieci" (NetworkMonitor dostępny). Mapowanie prezentacyjne.
- **i18n:** guest-visible EN hardkod: QR sheet ("Scan to get the video"),
  share subject/message, SMS sheet, toasty ("Saved to Photos"), etykiety kafli.
- **Paleta:** AnimatedDemoPreviewCard = fuchsia + hardkod `Color(red:.10,.10,.16)`;
  upload-failed raw `Color.red` zamiast `BoothifyTheme.error`.
- **Empty:** "Job not found" = goły tekst (wireframe-tier) — jest
  `BoothifyEmptyState`.
- **Reveal:** brak momentu reveal (video po prostu jest); satysfakcja przejścia
  = NEEDS-DEVICE, ale delikatne wejście (scale+fade przy pojawieniu) tanie.
- **QR sheet:** duży kod ✓, URL pod spodem ✓, Copy ✓ — dobry.

## B. Stany przekrojowo

- Wzorce OK: permission overlay (Recording), uploadStatusBar (Result),
  Booth360EmptyState (Landing), skeleton CloudStatusPanel, StatusOverlay
  (thermal HUD — operator, nie gość ✓), storage-Alert.
- Braki: Result "Job not found" (goły), Processing failed bez retry,
  offline≠failure (jw.), attract bez stanu "render w toku".

## C1. Event Hub — `Booth360EventHubView.swift` (543 L) — **OK+**

- Glanceable: staty/nagrania/cloud/share ✓; kiosk button ✓ (Phase 1 port);
  perf banner ✓ (Phase 8). Kolor kiosk buttonu amber ✓.
- Empty "Event not found" = goły tekst (jak Result).
- Operator-facing → EN OK.

## C2. Perf banner — w hubie (Phase 8) — **OK**

- Amber, konkretny komunikat z PerfBudget.operatorMessage, ikona gauge ✓.
  Verdict "fits" = brak banera ✓ (nie alarmuje bez powodu). Zostaje.

## D1. Landing — `Booth360LandingView.swift` (392 L) — **OK+**

- Template chips ✓ (Phase 1 port, amber), empty state ✓, create card ✓.
  Jedna główna akcja ✓. Operator-facing.

## D2. Settings — `SettingsHubView` + karty — **OK**

- Motion card ✓ (honest copy), Soundtrack & bumpers + licensing ✓ (Phase 5),
  stabilization picker z crop preview + device-gate + v2 lock ✓ (Phase 6).
- Brak: trigger picker (TriggerStateMachine z Phase 8 bez UI wyboru) — to
  FUNKCJA (wiring), nie polish → poza zakresem tego biegu, do logu.

---

## Plan polishu (kolejność briefu)
A1 attract → A2 capture → A3 processing → A4 result → B stany → C hub empty →
D (drobiazgi). Gate + commit per ekran.
