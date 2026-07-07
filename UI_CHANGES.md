# Boothify 360 — UI POLISH: co zmienione (brief §5)

Audyt wejściowy: `UI_AUDIT.md`. Gate (build + 54 testy) zielony po każdym
ekranie; commit per ekran: `f5e5e19` (A1) · `daaca7c` (A2) · `be20a6f` (A3) ·
`ab5e3e5` (A4) · `8af2857` (B/C/D).

## Zmienione per ekran

### A1 Kiosk Attract (`KioskAttractView.swift`)
- **Marka operatora = bohater**: uploaded logo / sample / watermark-text z
  brandOverlay; glif 360 tylko jako fallback bez brandingu. Skala „z 3 metrów".
- Akcent violet → **amber** (spójna opowieść 360 na całej ścieżce gościa);
  CTA czarny-na-amber (kontrast z dystansu).
- **Nowy stan**: spokojny pill „Poprzednie wideo się kończy — możesz zaczynać"
  (AppState.hasActiveRenders; budka nieblokująca — uspokajamy, nie blokujemy).
- „Powered by Boothify" → prawie niewidzialne „Boothify" (scena operatora).
- Fallback tytułu zlokalizowany; spacing → tokeny; reduce-motion = statyczny
  wariant wciąż zapraszający.

### A2 Recording (`Booth360RecordingView.swift`)
- **Higiena kiosku**: gear + Music/Presets = kontrolki operatora → ukryte przy
  `app.isKiosk` (gość ma czystą scenę z jednym przyciskiem; back zostaje jako
  ucieczka do attract; tytuł optycznie wycentrowany spacerem 44 pt).
- **Choreografia countdownu**: „Przygotuj się" → amber „START!" pod cyframi
  220 pt — synchronizuje gościa ze startem obrotu.
- **Uczciwa ramka cropu**: rysuje się TYLKO gdy preset stabilizacji ≠ Off
  (filozofia Phase 6 — ramka nie kłamie).
- Copy gościa zlokalizowane („Dotknij — start…", „Trzymaj pozę — kręcisz
  się!"). Raw `.red` → token `BoothifyTheme.recording`.

### A3 Processing (`Booth360ProcessingView.swift` + etykiety kroków w `Booth360.swift`)
- Ring amber→fuchsia→amber → **cichy jednobarwny amber sweep**; drugi glow
  fuchsia → violet (paleta), ciszej.
- **Cały ekran EN/PL/DE**: tytuł, statusy, 5 przepisanych tipów budujących
  oczekiwanie („Twój kod QR za kilka sekund"), etykiety kroków przepisane
  uczciwie i ciepło („Szlifuję wygląd" zamiast nadobiecującego „Applying AI
  cinematic effects").
- **Failed = naprawialny**: token error + NOWY „Spróbuj ponownie" (raw jest
  trzymany na failure dokładnie po to); Back jako secondary.
- Kiosk: „Wideo dokończy się w tle" WIDOCZNE nad „Następny gość" (było tylko
  w a11y-hint).

### A4 Result (`Booth360ResultView.swift`)
- **UI dogania Phase 7**: QR/SMS/Copy/Share odblokowane gdy `publicShareURL`
  istnieje (od SIGN), nie po zakończeniu uploadu; sheety prze-bramkowane;
  copy uploadu: „Wysyłanie — Twój QR już działa".
- **Offline ≠ awaria**: failed bez sieci → spokojna amber karta „W kolejce —
  brak sieci / QR nadal działa" (replay sam odpali po sieci); czerwień
  zostaje dla realnych błędów. Raw red → token error.
- **Reveal beat**: podgląd wjeżdża scale+fade (BoothifyMotion.bouncy;
  reduce-motion = natychmiast).
- Demo-preview: fuchsia + hardkod ciemnego → violet + token bg.
- „Job not found" → zaprojektowany `BoothifyEmptyState` z drogą dalej.
- Copy widoczne dla gościa zlokalizowane: QR sheet, SMS sheet, subject/message
  share'a, kafle, toasty.

### B/C/D
- Hub „Event not found" → `BoothifyEmptyState` z podpowiedzią przyczyny.
- Stabilizacja: **Cinematic Extended widoczny jako roadmap** („coming in a
  later update") zamiast po cichu odfiltrowany.

## Świadomie zostawione (i czemu)
- **Storage-low = systemowy Alert** (Recording) — to twardy bloker przed
  nagraniem; Alert jest jednoznaczny i nie wymaga własnego wzorca.
- **Permission overlay po angielsku** — instrukcja dla OPERATORA (naprawa w
  iOS Settings); granica językowa projektu: operator-UI EN.
- **QuickPresetsSheet / SettingsHub copy EN** — operator-facing.
- **Perf banner bez zmian** — spełnia brief C2 (amber, konkretny, verdict
  „fits" = brak banera).
- **Trigger picker (wybór manual/timer/motion) BRAK w ustawieniach** — to
  wiring FUNKCJI (TriggerStateMachine z Phase 8 → UI), nie polish; poza
  zakresem tego biegu. Zalogowane tu zamiast udawać, że to kwestia pikseli.
- **REC/„nagrywanie" czerwień** — stokenizowana, ale zostaje czerwona
  (uniwersalna konwencja REC, nie dekoracja).

## NEEDS-DEVICE (symulator tego nie rozstrzyga)
- Feel attract loopa (pulse 1.6 s przez godziny; szew pętli), czytelność marki
  operatora i CTA **z 3 metrów**.
- Satysfakcja reveal beat (bouncy na realnym wideo) i przejścia processing→result.
- Choreografia „Przygotuj się→START!" względem fizycznego startu ramienia.
- Haptics całej ścieżki gościa; beepy countdownu w głośnej sali.
- Czytelność countdownu 220 pt + cue w pełnym słońcu / scenicznym świetle.
- Amber-na-czerni kontrast attract CTA na realnym panelu iPada (nie sRGB sim).

## Tokeny dodane do BoothifyTheme
- `recording` — czerwień wskaźnika REC (jedyne miejsce czerwieni-konwencji;
  koniec z raw `.red` w widokach).
(Innych nie dodano — paleta/spacing/radius pokryły wszystko; hardkody
zastąpione istniejącymi tokenami.)
