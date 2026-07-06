# BUILD_REPORT — Boothify (Photobooth-ai, iOS)

Audyt z realnych plików (73 pliki Swift, 21 370 LOC, pełne drzewo przeczytane).
Stan na commit `d6608a4`. Weryfikacja: 3 niezależne przeglądy (ekrany+nawigacja,
warstwa danych, design system) + fakty potwierdzone w tej sesji buildami.

---

## 0. Core produktu

### Problem i user
**Problem:** firmy eventowe / fotografowie chcą sprzedawać atrakcję "AI photo booth"
na weselach, urodzinach i eventach firmowych — bez sprzętu za dziesiątki tysięcy
i bez ekipy. Konkurent-benchmark: **LumaBooth** (jawnie, w docs i komentarzach).

**User = OPERATOR (B2B)** — właściciel fotobudki, agencja eventowa, fotograf.
To on płaci subskrypcję i konfiguruje event. **Gość** eventu jest drugim userem
(consumer surface: kiosk, kamera, wynik, album webowy) — ale nie płaci i nie ma konta.

### Value prop (jedno zdanie)
Postaw iPada na evencie i sprzedawaj portrety AI + klasyczne foto-atrakcje
(strip, GIF, green screen, 360) z white-label brandingiem, drukiem i dostawą
na telefon gościa — działające także **całkowicie offline, bez AI API**.

### Job to be done
Operator otwiera apkę, żeby **w kilkadziesiąt sekund odpalić skonfigurowaną budkę
na dzisiejszym evencie** (template → event → kiosk) i mieć spokój do końca imprezy.

### Core loop (główna ścieżka, za każdym razem)
```
[Operator] Landing → nazwa+template → Create → EventHub → "Start Kiosk Mode"
[Gość]     Attract (tap) → CameraScreen (odliczanie, zgoda) → zdjęcie
           → StylePicker (22 style AI)  → upload → ResultView (poll → reveal)
           → LUB InstantLooks (on-device, 0 API) → wynik natychmiast
           → Save / Print (AirPrint) / QR / SMS / Email / ankieta → powrót do Attract
[Operator] EventHub: statystyki, capacity, galeria, slideshow/Event Wall, CSV leadów
```

### Funkcje: CORE vs SUPPORTING vs NICE-TO-HAVE

**CORE (bez tego apka nie ma sensu):**
- Capture (CameraScreen.swift, 1197 LOC) — foto/GIF/slow-mo, odliczanie, zgoda
- AI restyle 22 style (StylePickerView → BoothifyAPI → Gemini backend)
- **Instant Looks — no-AI path** (InstantLooksView + LocalLookProcessor, 12 looków
  Core Image) — strategiczna decyzja: budka działa bez internetu/billingu
- ResultView (1275 LOC) — reveal, QR/SMS/Email/share/print/save
- Event lifecycle (PhotoboothLandingView + EventHubView + EventTemplate 1-tap setup)
- Kiosk Mode (KioskAttractView + AppState.kioskEventId) — lock na jeden event, PIN exit

**SUPPORTING:**
- 19+ ekranów ustawień per-event (SettingsHubView + SettingsDetailViews +
  SettingsMVPViews) — druk, branding, disclaimer, ankieta, sharing, PIN
- Green screen on-device (BackgroundReplacer, Vision) + 8 studio backdrops
- Photo strip z JEDNEGO zdjęcia (PhotoStripComposer) i Look Reel MP4 (LookReelComposer)
- Slideshow / Event Wall (SlideshowView — QR do albumu /e/slug, Ken Burns)
- Offline queue (PhotoUploadQueue, 5 prób, replay po powrocie sieci)
- Lokalizacja gościa EN/PL/DE (Loc.swift, runtime)
- Auth: Sign in with Apple (LoginView + AuthClient, bearer+refresh, Keychain)
- StoreKit 2 (StoreManager + PaywallView)
- CSV export leadów z ankiet (CSVExporter)

**NICE-TO-HAVE / częściowe:**
- 360 AI Booth (Booth360* — pełny UI flow, render przez lokalny FFmpeg passthrough
  lub mock; backend renderu nie istnieje)
- Onboarding quiz (personalizacja pierwszego eventu)
- Kalendarz eventów (EventsCalendarView; sync z kalendarzem = Coming soon)
- Twilio self-service (TwilioOnboardingSheet — własny numer SMS operatora)

### Model biznesowy
**B2B subskrypcyjny, freemium przez trial.** StoreKit 2, 3 tiery
(Starter/Pro/Business, grupa "Boothify", 14-dniowy trial) — `StoreManager.swift:28`.
Web ma równoległą ścieżkę Stripe (US billing). **Uwaga:** `PremiumFeature.canUse`
istnieje, ale NIE gate'uje flow — celowo, bo produkty w App Store Connect jeszcze
nie istnieją (sandbox tier = zawsze .free → gating zablokowałby apkę).

### ZAIMPLEMENTOWANE vs ZASZKICOWANE

| Status | Co |
|---|---|
| ✅ Działa (zweryfikowane) | Cały photobooth flow UI, Instant Looks/strip/reel/backdropy, kiosk, ustawienia (persist do UserDefaults), auth, offline queue, i18n, paywall UI, analytics hubu, Event Wall |
| ✅ Kod gotowy, czeka na klucze | Revokacja tokenu Apple (uśpiona do czasu APPLE_TEAM_ID/KEY_ID/.p8), StoreKit (czeka na produkty ASC) |
| ⚠️ Zablokowane zewnętrznie | **Generacja AI — Gemini 429 (brak płatnego billingu)**; backend musi stać (BOOTHIFY_API_BASE_URL) |
| ⚠️ Tylko na urządzeniu | Green screen/backdropy (Vision nie działa w symulatorze), live kamera, multi-capture |
| 🔶 Zaszkicowane/mock | 360: render = MockBooth360RenderClient / FFmpeg passthrough (Booth360.swift:169, 300); publicShareURL częściowo mock |
| 🔒 Ukryte celowo | Panel Effects (beautify/filtr/ziarno/winieta) — ustawienia zapisywały się, ale NIE są używane nigdzie w pipeline; ukryty z huba (SettingsHubView), widok+route zostały |
| ❌ Nie istnieje | Testy (zero targetów testowych), sync kalendarza, entitlement enforcement |

### Pytania / wątpliwości produktowe (niejasne lub sprzeczne w kodzie)
1. **360 Booth — shippować czy wyciąć z v1?** UI jest kompletny (5 ekranów, 2,6k LOC),
   ale render to mock/passthrough, a web ukrywa 360 przed gośćmi
   (`MVP_HIDE_AI360_FROM_GUESTS=true`). Utrzymywanie martwej połowy apki vs beta badge.
2. **Kto jest targetem paywalla?** Tiery istnieją, ale nic nie jest gate'owane — brak
   w kodzie decyzji CO konkretnie jest premium (ile stylów? kiosk? white-label? druk?).
3. **Dane ankiet/zgód tylko lokalnie** (UserDefaults per event) — operator z 2 iPadami
   nie zsumuje leadów; backend table "planned" ale nie ma kontraktu. MVP czy dług?
4. **Min iOS = 26.2** (project.pbxproj) — bardzo świeży target; świadoma decyzja
   (tnie starsze iPady, na których często stoją budki!) czy przypadkowy default Xcode?
5. **Stickers vs Brand Overlay** — StickerSettings zostawione "for backward-compat",
   UI usunięte; EffectsSettings analogicznie ukryte. Czy czyścimy model w v2, czy
   te ficzery wracają?

---

## 1. Overview

- **Architektura:** plain SwiftUI + `@Observable` (Observation framework). Jeden
  centralny `AppState` (MainActor, wstrzykiwany przez `.environment`), bez MVVM
  per-ekran, bez TCA. Nawigacja: `NavigationStack` + `NavigationPath` + enum `Route`.
- **Min iOS:** `IPHONEOS_DEPLOYMENT_TARGET = 26.2`; `TARGETED_DEVICE_FAMILY = "1,2"`
  (iPhone + iPad).
- **Zależności (SPM, brak Pods/Carthage):**
  - `ffmpeg-kit-spm` (tylerjonesio, pinned revision) — transcoding 360
  - `sentry-cocoa` ≥ 9.9.0 — crash reporting (DSN jeszcze niepodpięty = TODO-human)
- **System frameworks:** Vision, CoreImage, AVFoundation, ImageIO, Network,
  StoreKit 2, LocalAuthentication, PhotosUI, CryptoKit.
- **Testy: BRAK** (zero targetów testowych). Realne TODO w kodzie: **2**
  (oba `TODO(human)` — produkty StoreKit).
- **Docs:** bogate (root: PROGRESS/DECISIONS/UX_AUDIT/TODO-HUMAN…, docs/:
  LAUNCH-CHECKLIST, APP-REVIEW, FINISH-PLAN). **Brak README.md.**

## 2. Struktura ekranów

Wszystkie 31 route'ów ma działające destination — **zero martwych route'ów**.
(Pełna 27-wierszowa tabela per plik — status/nawigacja/dane — poniżej skrócona
do informacji decyzyjnej; każdy plik przeczytany.)

| Ekran (plik) | LOC | Status | Dane |
|---|---|---|---|
| RootView (tab bar, AppSettings, Profile, auth gate) | 742 | DONE | API+AppState+StoreKit |
| ModeSelectionView (Home: wybór trybu) | 325 | DONE | StoreManager (tier badge) |
| PhotoboothLandingView (nowy event + templates + recent) | 549 | DONE | API (create/list) |
| EventHubView (konsola operatora: staty, capacity, share) | 737 | DONE | API (photos, event refresh) |
| CameraScreen (foto/GIF/slow-mo, zgoda, hint) | 1197 | DONE | on-device; placeholder w sim |
| StylePickerView (22 style AI + wejście Instant) | 373 | DONE | API upload; offline queue |
| InstantLooksView (12 looków, strip, reel, backdropy) | 457 | DONE | 100% on-device |
| ResultView (poll → reveal, share/QR/SMS/email/ankieta) | 1275 | DONE | API poll |
| GalleryView / SlideshowView (grid / Event Wall+QR) | 236/318 | DONE | API |
| EventsCalendarView (tab Events; calendar-sync = locked) | 459 | DONE (1 stub-banner) | API |
| LoginView (Sign in with Apple + nonce + authCode) | 206 | DONE | AuthClient+Keychain |
| OnboardingQuiz (first-run, seed ustawień) | 545 | DONE | lokalnie (OnboardingStore) |
| PaywallView (plany, Restore, linki prawne, okres dynamiczny) | 163 | DONE (pusty stan do czasu produktów ASC) | StoreKit 2 |
| PinGateView (PIN+biometria, rate-limit 3/30s) | 254 | DONE | settings.lockPin |
| SettingsHubView + SettingsDetailViews + SettingsMVPViews | 397+1009+1899 | DONE | UserDefaults per event |
| KioskAttractView (attract loop, exit=long-press+PIN) | 147 | DONE | AppState |
| TwilioOnboardingSheet (SID/API-key, test SMS) | 372 | DONE | TwilioClient+Keychain |
| Booth360: Landing/Hub/Recording/Processing/Result | ~2600 | UI DONE / **pipeline MOCK** | FFmpeg passthrough lub mock |
| ContentView | 13 | STUB (wrapper na RootView, legacy) | — |
| ComingSoonView (route .settingsComingSoon) | — | placeholder BY DESIGN (obecnie nieaktywny) | — |

## 3. Nawigacja

- **System:** jeden `NavigationStack(path:)` w RootView; `Route: Hashable` (31 case'ów,
  AppState.swift:475–517); switch destination w RootView.swift:88–216. Helpery:
  `app.push/pop/popToRoot/popUntil`.
- **Tab bar:** custom `BoothifyTabBar` (3 taby: Booth/Events/Settings), ukryty w kiosku.
- **Sheets:** Paywall, OnboardingQuiz, QR/Email/SMS/Survey, Twilio, BetaPreview.
- **Kiosk:** `kioskEventId != nil` ⇒ root = KioskAttractView; gość zamknięty w pętli
  capture (Result popUntil→attract); wyjście long-press+PIN. Celowy "lock", nie dead-end.
- **Dead-endy: brak.** Każdy ekran ma pop/system-back; Result robi popUntil do huba.
- **Crash restore:** CrashRestoreManager przywraca ostatni aktywny event po relaunchu.

## 4. Design system

- **Istnieje i jest dyscyplinowany.** Tokeny: `BoothifyTheme` (kolory; akcent
  `violet` = wartość blue-500 — nazwa legacy), `BoothifyRadius` (7), `BoothifySpacing`
  (6), `BoothifyType` (12+ semantycznych fontów), `BoothifyMotion` (4 krzywe +
  wrapper reduce-motion). 4 ButtonStyles, 13 komponentów współdzielonych
  (AppCard/AppEmptyState/AppListRow/AppStatusPill/Surface/…), centralne `Haptics`
  (177 wywołań / 27 plików).
- **Dark/light:** **dark-only, twardo** — `preferredColorScheme(.dark)`
  (Photobooth_aiApp.swift:22), kolory fixed (nie semantic `Color(.label)`).
  Light mode architektonicznie niewspierany. Dla booth-appki OK, ale to decyzja,
  nie przypadek.
- **Hardcoded poza tokenami (miejsca):**
  - `Color(red:)` poza Theme: **30×** — Models.swift 20× (celowe gradienty stylów),
    **ResultView.swift:887–891 duplikuje violet/emerald/amber/fuchsia z Theme (DRY!)**,
    RootView.swift:258 i Booth360ResultView.swift:556 (bespoke gradienty tła)
  - cornerRadius literały: **71×, ~50% poza skalą** (wartości 4/6/9/10/26/28 nie mają
    tokenów) — najgorzej: SettingsMVPViews (15×), Booth360ResultView (15×),
    PhotoboothLandingView (7×). Największa okazja do konsolidacji.
  - padding literały: **13×** (~87% zgodności) — m.in. SettingsMVPViews:790/888/894,
    ModeSelectionView:184/189
  - `.font(.system(size:))`: 25× — z czego 8 przez `@ScaledMetric` (OK), 3 celowe
    (countdown 200–220pt); ryzyko Dynamic Type niskie
- **Dostępność:** 60 accessibilityLabel, **85 guardów reduce-motion** (wzorowo),
  8 `@ScaledMetric`. Tap targets 44pt+ na kluczowych ekranach.

## 5. Warstwa danych

- **Modele:** APIModels.swift (Event/Photo/PhotoList/ShareMode/Booth360JobDTO/
  GeminiQuota), Models.swift (PhotoStyle ×22, PhotoStatus), EventSettings.swift
  (**17 sekcji ustawień**, dekoder odporny na brakujące klucze — Optional pattern),
  Booth360.swift (Job/Status/Steps/protokół klienta).
- **Sieć:** BoothifyAPI (singleton; base z Info.plist `BOOTHIFY_API_BASE_URL`,
  default localhost:3000; bearer + auto-refresh na 401 z retry ×1; timeouts 12/30s).
  Endpointy: events CRUD, photos upload/generate/poll, booth360 jobs, public URLs
  (`/p/{id}`, `/e/{slug}`). AuthClient: apple/refresh/delete-account.
  TwilioClient: REST Messages (kredki w Keychain). Typowany `APIError`
  z flagą isRetryable (w tym `quota_exceeded` dla Gemini 429).
- **State:** `@Observable AppState` (MainActor) — events, session, path, kiosk,
  settings-cache. **Persist:** sesja → Keychain; EventSettings → UserDefaults
  per-event; kolejki → Application Support (JSON+JPEG); Twilio → Keychain.
- **Offline:** PhotoUploadQueue (max 5 prób, replay na launch + powrót sieci),
  Booth360UploadQueue (idempotencja przez client_job_id), NetworkMonitor (NWPath).
- **Mock/local-only:** MockBooth360RenderClient + PassthroughClient (360 render),
  `Event.localDemo` przy `authGateEnabled=false` (DEBUG only; Release zawsze ON),
  placeholder capture w symulatorze, ankiety+zgody tylko lokalnie.

## 6. Stan UI/UX per ekran

| Ekran | UI % | Problemy UX | Do "premium" brakuje |
|---|---|---|---|
| CameraScreen | 95 | — (hinty zlokalizowane, busy states OK) | weryfikacja na urządzeniu (live preview, multi-capture) |
| StylePicker | 95 | — (face-guard, offline queue, Retake jest) | realne preview stylów zamiast gradientów gdy brak sampli |
| InstantLooks | 95 | — (busy overlay, i18n, sekcje) | backdropy do potwierdzenia na urządzeniu (Vision) |
| ResultView | 90 | plik 1275 LOC — utrzymaniowo ciężki | rozbić na podwidoki; kolory z Theme zamiast duplikatów (887–891) |
| EventHub | 95 | — (staty server-accurate, capacity meter) | żywe liczby wymagają backendu |
| Landing/Templates | 95 | — | — |
| Kiosk Attract | 90 | — | branding operatora (logo) na attract |
| Slideshow/Event Wall | 90 | niewidoczne w sim (AsyncImage) | test na TV/urządzeniu |
| Gallery | 85 | brak paginacji (limit 200) | pull-to-refresh + paging przy dużych eventach |
| Settings (19 ekranów) | 90 | SettingsMVPViews 1899 LOC — moloch | rozbić plik; radius/padding na tokeny |
| Paywall | 85 | pusty stan do czasu produktów ASC | badge "najpopularniejszy", porównanie tierów |
| Login/Onboarding | 95 | — | — |
| EventsCalendar | 80 | calendar-sync = zamknięty banner | realny EventKit sync albo usunąć banner |
| Booth360 (5 ekranów) | UI 90 / pipeline 30 | render mock/passthrough; "fake timer" w recording | realny backend renderu ALBO wycięcie z v1 |
| Profile card | 85 | staty mogą być nieświeże do refetchu | onChange refresh |

## 7. Luki i długi techniczne

**Blokery launchu (zewnętrzne, poza kodem):**
1. **Gemini billing** — każda generacja AI = 429 (`ai-photobooth/src/lib/gemini/client.ts`).
2. Backend live + `BOOTHIFY_API_BASE_URL` na prod.
3. Migracje Supabase **14** (claim_photo_slot) i **15** (apple_refresh_token) niezaaplikowane.
4. Produkty ASC + sandbox test; potem wpiąć entitlement enforcement.
5. Klucze Apple (.p8/KeyID/TeamID) → aktywacja revokacji tokenu.
6. **Zero weryfikacji na fizycznym urządzeniu** (kamera, Vision, druk, 360).

**Dług w kodzie (wewnętrzny):**
- **Testów brak w ogóle** — największy pojedynczy dług; minimum: unit na EventSettings
  decode-compat, PhotoUploadQueue retry, APIError mapping.
- Pliki-molochy: SettingsMVPViews **1899**, ResultView **1275**, CameraScreen **1197** LOC
  (łamią własną zasadę małych komponentów).
- cornerRadius: 71 literałów/50% poza skalą; ResultView duplikuje 4 kolory Theme.
- Martwe-ale-obecne: EffectsSettings (ukryte, niepodpięte do pipeline),
  StickerSettings (legacy compat), route `.settingsComingSoon` (infrastruktura).
- 360: `rawVideoLocalURL` mock, "fake timer" w RecordingView, share URL częściowo mock.
- Ankiety/zgody bez syncu do backendu (lokalne UserDefaults).
- Sentry wpięty, ale bez DSN = martwy.
- Min target 26.2 do świadomego potwierdzenia (odcina starsze iPady).
- Brak README.md (docs są, ale wejścia do repo brak).

**Niespójności drobne:**
- Token `violet` ma wartość niebieską (rename odłożony świadomie — komentarz w Theme).
- "Quick Setup" duplikuje 3 wiersze z sekcji niżej (celowy skrót — zostawione).
- ContentView to 13-liniowy legacy wrapper — do usunięcia przy porządkach.
