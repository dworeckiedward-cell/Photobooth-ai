# Boothify 360 — pełny opis aplikacji

> Ostatnia aktualizacja: 2026-07-15 (commit `ce37a70`).
> Ten dokument to przewodnik po całości — co appka robi, jak jest zbudowana
> i gdzie szukać szczegółów. Dokumenty techniczne (kontrakty, decyzje, audyty)
> są po angielsku i podlinkowane na końcu.

---

## 1. Czym jest Boothify 360

Natywna aplikacja iOS (SwiftUI, iOS 17+) dla **operatorów budek 360** —
firm eventowych, które stawiają na weselach/imprezach obrotowe ramię
z iPhone'em. Przebieg jednego "spinu":

1. Gość wchodzi na platformę, operator (albo sam gość w trybie kiosku) tapie START.
2. iPhone na ramieniu nagrywa kilkusekundowy obrot w wysokim fps.
3. Appka **na urządzeniu** renderuje z tego brandowany klip MP4: szablon ruchu
   (slow-mo, rampy prędkości, reverse), overlay z logo operatora, intro/outro,
   muzyka — bez chmury, bez AI, bez kosztu za render.
4. Gość dostaje wideo od razu: QR kod na ekranie, link, SMS (Twilio), e-mail
   albo AirDrop. Upload do chmury idzie w tle z kolejką offline-safe.

**Model biznesowy:** subskrypcja operatorska (StoreKit 2), brak opłat per render.
**Konkurencyjny wyróżnik:** cała produkcja wideo lokalnie na telefonie —
działa bez internetu na evencie, delivery dogania po odzyskaniu sieci.

---

## 2. Architektura wysokopoziomowa

```
┌─────────────────────  iPhone (ta appka)  ─────────────────────┐
│                                                                │
│  SwiftUI UI  ──▶  AppState (@Observable, jeden NavigationStack)│
│                     │                                          │
│  CameraController (AVCaptureMovieFileOutput, wysoki fps)       │
│                     │  surowy klip .mov                        │
│  Booth360RenderEngine (AVComposition + VideoToolbox H.264,     │
│    per-frame CoreImage overlay, chunked reverse encoder)       │
│                     │  finalny .mp4                            │
│  Delivery: QR / SMS / e-mail / AirDrop + Booth360UploadQueue   │
└───────────────┬────────────────────────────────────────────────┘
                │ HTTPS (upload + short-link)
┌───────────────▼───────────────────────────────────────────────┐
│  Backend: Next.js + Supabase (repo ai-photobooth)              │
│  https://ai-photobooth-rust.vercel.app                         │
│  – strony publiczne  /v/{short} (wynik) i /e/{slug} (galeria)  │
│  – storage wideo, short-linki, eventy                          │
└────────────────────────────────────────────────────────────────┘
```

Appka **degraduje się łagodnie** bez backendu: render i lokalne delivery
(QR do pliku, AirDrop, zapis) działają zawsze; upload czeka w kolejce.

---

## 3. Przepływy (Route enum — [AppState.swift:663](Photobooth-ai/AppState.swift:663))

### Przepływ gościa (guest-facing, EN/DE)
`booth360Landing` → `booth360EventHub` → `booth360Recording`
(countdown + nagranie) → `booth360Processing` (ring postępu, non-blocking —
"Next guest" nie zabija renderu) → `booth360Result` (podgląd wideo, QR hero,
SMS/link/zapis + **ankieta post-result** raz na klip).

### Tryb kiosku
`KioskAttractView` — pełnoekranowy "TAP TO START" z brandingiem operatora,
Guided Access / Single App Mode, wyjście przez long-press + Lock PIN
(PIN w Keychain, per event). Renderowanie w tle nie blokuje kolejnego gościa.

### Operator
- **Eventy:** kalendarz (`EventsCalendarView`), szablony eventów, marker
  „live event" (Continue/End banner).
- **Ustawienia per event** (`settings360Hub` + poddrzewa): kamera, jakość/eksport
  (fast share / best quality), szablony ruchu, overlay/brand, muzyka + guardrail
  licencyjny, sharing (QR/SMS/e-mail), disclaimer, ankieta, Lock PIN, konto.
- **Delivery/CRM:** eksport ankiet i leadów do CSV (`CSVExporter`),
  status uploadów (`CloudStatusPanel`).
- **Monetyzacja:** `PaywallView` + `StoreManager` (StoreKit 2, entitlement gating).

### Deep linki (universal links)
`https://ai-photobooth-rust.vercel.app/e/{slug}` → hub eventu,
`/v/{short}` → ekran wyniku. Obsługa w `AppState.handleDeepLink`
(guard na tryb kiosku). Wymaga wdrożenia pliku AASA z prawdziwym Team ID
(instrukcja: HANDOFF §F+).

---

## 4. Pipeline renderowania (serce appki)

| Etap | Plik | Co robi |
|------|------|---------|
| Nagranie | `CameraController.swift` | AVCaptureMovieFileOutput, wysoki fps; w symulatorze mock |
| Spec | `RenderSpec.swift`, `MotionTemplates.swift` | 3 szablony ruchu, rampy prędkości, honesty clamp (nie obiecuje fps, którego nie było) |
| Silnik | `Booth360RenderEngine.swift` | AVMutableComposition + AVAssetReader/Writer, VideoToolbox H.264 |
| Reverse | `Booth360ReverseEncoder.swift` | odwrócone segmenty enkodowane chunkami (stała pamięć) |
| Dekoracje | `RenderDecorationsBuilder.swift`, `OverlaySpec.swift` | per-frame overlay CoreImage; walidacja assetów (przezroczystość obowiązkowa, aspekt musi się zgadzać) |
| Stabilizacja | `StabilizationPreset.swift` | presety |
| Budżety | `PerfBudget.swift`, `ThermalMonitor.swift` | limity czasu/termiki |
| Klient | `Booth360NativeRenderClient.swift` | orkiestracja jobu (`Booth360Job`) |

Joby żyją w `AppState.booth360Jobs` i **przeżywają restart appki**
(UserDefaults `boothify.booth360Jobs.v1`; przerwane rendery wracają jako
`.failed` z komunikatem, martwe URL-e plików są czyszczone).
Zapisane pliki zarządza `StorageLifecycle` (przy niskim miejscu: najpierw
surowe nagrania, potem połowa masterów, najnowsze zostają).

---

## 5. Niezawodność i bezpieczeństwo

- **Kolejka uploadów** (`Booth360UploadQueue`) — retry z backoffem, offline-safe.
- **Crash recovery** (`CrashRestoreManager`) — odzyskiwanie po padzie w trakcie sesji.
- **Keychain** (`KeychainStore`) — sesja auth, tokeny Twilio, **Lock PIN per event**
  (`boothify.lockpin.<eventId>`); legacy PIN migruje z UserDefaults i jest
  wymazywany z blobu (custom Codable nigdy nie enkoduje pinu).
- **Auth** (`AuthClient`/`AuthSession`) — Sign in with Apple; w DEBUG bramka
  wyłączona, chyba że `BOOTHIFY_REQUIRE_AUTH=1` (`AppConfig.authGateEnabled`).
- **Monitoring** — `SentryClient` (crash reporting), `NetworkMonitor`.
- **Honesty rules** — appka nie kłamie w copy (po audycie P1): żadnych
  obietnic AI/druku/funkcji, których nie ma.

---

## 6. Design system i UX

Dark-only, "black era": tło niemal czarne, **fiolet-500 jako jedyny akcent**
(amber tylko semantycznie dla ostrzeżeń). Kluczowe komponenty
(`AtmosphericGlass.swift`, `DesignSystem.swift`, `Theme.swift`,
`Typography.swift`, `MotionTokens.swift`):

- `GlassSurface` — glassmorphism (materiał + ukośny sheen + doświetlony rim),
- `AmbientVideoView` — zapętlone wideo BoothAmbient.mp4 jako tło Home z parallaksą,
- pływająca pill-nawigacja (`BoothifyTabBar`), `EntranceReveal` (staggered),
  `AccentCTAButtonStyle`, `LaserCapsuleBorder`, `SettingsSectionCard`.

Zasady kompozycji: oddech zamiast cegieł, jedna dominanta na ekran, akcja
świeci (CTA z glow), pełne wsparcie reduce-motion i Dynamic Type,
touch targets 44 pt. Szczegóły: `DESIGN_SYSTEM.md`, `LAYOUT_CHANGES.md`.

**Lokalizacja:** `Loc.t(en:de:)` — runtime EN (default) + DE dla stringów
widzianych przez gości; UI operatora po angielsku. Polski celowo usunięty
(decyzja rynkowa 2026-07-07).

---

## 7. Backend (repo `ai-photobooth`)

Next.js + Supabase, deploy: `https://ai-photobooth-rust.vercel.app`.
Kontrakt: `BACKEND_CONTRACT.md`. Appka używa go do: uploadu finalnych MP4,
short-linków `/v/{short}`, publicznych galerii eventów `/e/{slug}`,
wysyłki e-mail. SMS idzie przez **Twilio operatora** (jego konto, jego koszt),
z onboardingiem w appce (`TwilioOnboardingSheet`).

---

## 8. Testy i jakość

- **Gate:** `./scripts/gate.sh` = build + pełna suita na symulatorze
  iPhone 17 Pro. **Jedyne kryterium merge'a.** Stan: 56 testów, 0 failures.
- Suita (`Photobooth-aiTests/`): render engine na syntetycznych klipach
  (`TestVideoFactory`), motion templates, stabilizacja, overlay/audio, upload
  queue, delivery policy, storage lifecycle, decode ustawień (w tym: PIN nigdy
  nie enkodowany), exhaustiveness routingu, hardening Phase 8.
- **Snapshoty layoutu:** `LayoutSnapshotTests` (opt-in przez
  `TEST_RUNNER_SNAPSHOT_DIR`) renderuje 8 ekranów do PNG.
- Symulator nie ma kamery — capture ma mock; render testowalny w pełni.

---

## 9. Status projektu (na dziś)

**v1 code-complete, device-unverified.** Blueprint v4 fazy 0–8 wykonane,
dług po audycie zamknięty (kłamliwe copy, utrata `progress` przy dekodzie,
relikty foto-ery, persystencja jobów, martwe `pl:`, PIN→Keychain, deep linki,
wskrzeszona ankieta).

**Czeka na człowieka** (pełna lista: `TODO-HUMAN.md`, `HANDOFF.md` §F,
`NEEDS_DEVICE.md`):
- test na fizycznym urządzeniu (kamera, termika, realny render) — Gate B,
- plik AASA z prawdziwym Team ID (deep linki),
- migracja Supabase nr 15 (+ decyzja o 14),
- App Store Connect: produkty subskrypcji, App Privacy label, age rating,
  disclosure Sentry, screenshoty (w tym iPad),
- natywne tłumaczenie opisu DE (metadane gotowe w `ASO_METADATA.md`).

---

## 10. Mapa dokumentów w repo

| Plik | Co zawiera |
|------|-----------|
| `README.md` | skrót + build & run |
| `HANDOFF.md` | przewodnik przekazania: architektura, sekrety, kroki human-only |
| `BACKEND_CONTRACT.md` | kontrakt API iOS ↔ backend |
| `PROGRESS.md` / `DECISIONS.md` / `DECISIONS_LOG.md` | log faz i decyzji produktowych |
| `AUDIT_REPORT.md` | audyt vs blueprint (co realne, co było overclaim) |
| `DESIGN_SYSTEM.md` / `LAYOUT_CHANGES.md` / `UI_CHANGES*.md` | system wizualny i historia redesignów |
| `UX_AUDIT.md` / `UI_AUDIT.md` | audyty heurystyczne |
| `ASO_METADATA.md` | zwalidowane metadane App Store (EN+DE), keywords, plan A/B, launch checklist |
| `PRIVACY.md` | polityka prywatności |
| `NEEDS_DEVICE.md` / `TODO-HUMAN.md` | co wymaga urządzenia / człowieka |
| `ASSUMPTIONS.md` / `OUT_OF_SCOPE_FOUND.md` / `QUICK_WINS.md` / `STRATEGIC_PROPOSALS.md` | założenia, znaleziska, pomysły |

**Kod:** 67 plików Swift w `Photobooth-ai/`, testy w `Photobooth-aiTests/`,
gate w `scripts/gate.sh`. Repo: `github.com/dworeckiedward-cell/Photobooth-ai`.
