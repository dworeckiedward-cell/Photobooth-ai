# Boothify — Master Execution Prompt (2–3 day autonomous finish)

> Wklej ten plik jako prompt do agenta z otwartymi OBOMA repozytoriami. Jest samowystarczalny.
> Towarzyszy mu `docs/FINISH-PLAN.md` (strategia/uzasadnienie). Pracuj **milestone po milestone**,
> commituj często, build zawsze zielony. Cel: dokończyć Boothify do **płatnego produktu rynkowego**
> klasy LumaBooth, zgodnego ze standardami Apple.

---

## 0. ROLA I NADRZĘDNA DYREKTYWA

Jesteś senior iOS/full-stack inżynierem + product designerem, który wypuszczał apki z półki
„Apps We Love". Twój próg jakości to natywne apki Apple (Camera, Photos), Things 3, Halide, Linear.
Dokańczasz **istniejącą** apkę — nie przepisujesz jej od zera.

**Zasada nadrzędna:** zachowaj działającą logikę. Naprawiaj/rozbudowuj świadomie, ale nie psuj
tego, co już działa produkcyjnie (lista w §3). Każda zmiana: build zielony + weryfikacja + commit.
Jeśli coś wymaga decyzji biznesowej/sekretu/billingu (klucze, ceny Stripe, konto Google) — **nie zgaduj**,
zostaw `// TODO(human):` z dokładną instrukcją i kontynuuj resztę.

## 1. REPOZYTORIA I STACK

- **iOS (natywne):** `/Users/edekdworecki/Projects/Photobooth-ai` — SwiftUI, iPad-first, design system
  `BoothifyTheme/Spacing/Radius/Type`, akcent = `BoothifyTheme.violet` (obecnie NIEBIESKI — token, nie ruszaj nazwy).
  Symulator iPhone 17 Pro UDID `283EE072-5EEC-4376-9299-87A6E7C8089C` (dodaj też iPada do testów).
- **Backend/web:** `/Users/edekdworecki/Projects/ai-photobooth` — Next.js 16, React 19, Tailwind v4,
  Supabase, Stripe, Gemini (`gemini-2.5-flash-image`). Prod: Vercel `ai-photobooth-rust.vercel.app`.
- iOS celuje w backend przez `BoothifyAPI.shared.baseURL` (Info.plist `BOOTHIFY_API_BASE_URL`).

**Komendy weryfikacji (używaj po każdej zmianie):**
```
# iOS build
xcodebuild -project /Users/edekdworecki/Projects/Photobooth-ai/Photobooth-ai.xcodeproj \
  -scheme Photobooth-ai -destination 'platform=iOS Simulator,id=283EE072-5EEC-4376-9299-87A6E7C8089C' \
  -configuration Debug build
# iOS install+launch+screenshot
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Photobooth-ai-*/Build/Products/Debug-iphonesimulator/Photobooth-ai.app | head -1)
xcrun simctl install <UDID> "$APP"; xcrun simctl launch <UDID> com.servify.Photobooth-ai
xcrun simctl io <UDID> screenshot /tmp/shot.png   # potem przeczytaj obraz
# backend
cd /Users/edekdworecki/Projects/ai-photobooth && npx next build
```
Uwaga: quiz onboardingu odpala się ~350ms po starcie (`RootView.swift .task`). Do headless
screenshotów ekranów za nim — tymczasowo wydłuż delay / ustaw domyślną zakładkę, potem COFNIJ.

## 2. PROTOKÓŁ PRACY (2–3 dni)

1. Czytaj najpierw. Zanim ruszysz milestone — przeczytaj zależne pliki w całości.
2. Trzymaj się kolejności **M0 → M4** (§4). W obrębie milestone'u realizuj zadania po kolei.
3. Po każdym zadaniu: build zielony → (jeśli UI) screenshot @ iPhone 17 Pro i iPad → ocena vs HIG → commit.
4. Commituj atomowo, sensowne wiadomości, kończ trailerem `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
   Na `main` commituj wprost (taki workflow repo) — chyba że zadanie mówi inaczej.
5. Po każdym milestone: zaktualizuj `docs/PROGRESS.md` (utwórz) — co zrobione, co zostało, TODO(human).
6. Nie pytaj o pozwolenie na rzeczy oczywiste; pytaj tylko o decyzje biznesowe/sekrety (zostaw TODO(human)).
7. Jeśli utkniesz na realnym blockerze (np. brak klucza) — udokumentuj, pomiń, jedź dalej z resztą.

## 3. NIE PSUJ (działa produkcyjnie)

capture→upload→Gemini→poll→result; share Save/Email/SMS/WhatsApp/QR/AirPrint; 360 (FFmpegKit, signed upload, retry);
Apple Sign In + refresh; offline queues + CrashRestore + NetworkMonitor; Lock PIN, Brand Overlay,
Virtual Attendant, Disclaimer, Survey, Delivery Status, album shareMode, SMS template+Twilio, Print, AI enabledStyles.
Backend: 34 route'y, pipeline Gemini, Stripe (kod). Prop-kontrakty między modułami, route paths, nazwy plików, schema API.

---

## 4. MILESTONE'Y (rób w tej kolejności)

### M0 — ODBLOKOWANIE I „PRAWDA" (priorytet absolutny)

**M0.1 Generacja AI — typed errors + UX (kod; billing to TODO(human)).**
- Backend `src/lib/gemini/generate.ts` / `src/app/api/photos/generate/route.ts`: gdy Gemini zwróci 429,
  mapuj na **typed kind `quota_exceeded`** i HTTP **429/503** (nie 500). Dziś Google 429 → 500 (audyt).
- iOS `APIError.swift` + `ResultView.swift`: rozpoznaj `quota_exceeded` i pokaż czytelny stan
  („Przekroczono limit AI — spróbuj za chwilę"), nie generyczny błąd.
- `// TODO(human): włącz billing Gemini (paid tier) i ustaw GEMINI_API_KEY w .env.local ORAZ Vercel prod → redeploy.`
- Accept: symulacja 429 pokazuje dedykowany komunikat; build obu repo zielony.

**M0.2 Race condition + quota backstop (backend).**
- `src/app/api/photos/generate/route.ts:~156`: zabezpiecz inkrement `completed_photos` vs `max_photos`
  (Postgres advisory lock `pg_try_advisory_xact_lock` lub `SELECT … FOR UPDATE` RPC).
- `src/lib/gemini/quota.ts`: dodaj **twardy backstop** budżetu (nie tylko fail-open) — gdy DB niedostępne,
  zastosuj konserwatywny limit zamiast przepuszczać wszystko.
- Accept: test współbieżny nie przekracza `max_photos`; opisz w PROGRESS.

**M0.3 Pogodzenie Settings z rzeczywistością (iOS) — NAJWAŻNIEJSZE dla wiarygodności.**
Dla KAŻDEJ martwej sekcji: albo zaimplementuj, albo oznacz „Coming soon"/ukryj. Zero przełączników bez efektu.
- **Capture** (`CaptureSettingsView` / `CameraScreen.swift:548`): podłącz **countdown** (czytaj z settings, nie hardkod 3),
  **liczbę zdjęć**, **jakość JPEG** (zamiast 0.85). GIF/roaming jeśli nietrywialne → „Coming soon".
- **Camera**: podłącz **`mirrorSelfie`** (dziś zawsze `true`), zoom/flash jeśli proste; reszta → „Coming soon".
- **Effects**: jeśli nie implementujesz w M0 → ukryj/„Coming soon" (NIE „available").
- **Gallery/Slideshow settings**: jak wyżej.
- Popraw badge w `SettingsHubView.swift` (`:85,94,100`) — „available" tylko dla realnie działających.
- Accept: przejdź każdą sekcję; każdy widoczny przełącznik albo zmienia zachowanie, albo jest jawnie „wkrótce".

**M0.4 Env validation + flagi release.**
- Backend: walidacja env na boot (schemat ~20 zmiennych: Stripe×10, Apple, JWT, Supabase, Twilio, Resend, Gemini) — brak = jasny błąd startowy.
- iOS: `AppConfig.swift:19` — upewnij się `authGateEnabled` ON w Release. `// TODO(human)` jeśli wymaga decyzji.

---

### M1 — CAPTURE PARITY (table-stakes LumaBooth)

**M1.1 Green screen / background removal (iOS, on-device).**
- Realne maskowanie: **Vision `VNGeneratePersonSegmentationRequest`** / CoreImage; tła per-event (kolor/obraz).
- Zastąp „Demo" w `BackgroundRemovalSettingsView` realnym pipeline; tło wybierane w settings i wgrywane (Supabase Storage bucket — patrz backend `photobooth-branding`).
- Wpięcie w ścieżkę capture/result (przed AI i/lub jako osobny tryb). Reduce Motion respektuj.
- Accept: zdjęcie z podmienionym tłem zapisuje się/drukuje/udostępnia poprawnie.

**M1.2 Multi-capture → AI → share/print.**
- GIF/boomerang/burst dziś dead-end (share sheet). Przeprowadź je przez pipeline tam, gdzie sensowne,
  oraz dodaj **photo-strip** (2/3/4 klatki) z layoutami druku (`PrintEngine` już ma single/2-strip/4-strip).
- Tryb capture **wybierany per-event** (photo/GIF/boomerang/video/360/green-screen) i respektowany w `CameraScreen`.
- Accept: każdy tryb przechodzi capture → (opcjonalnie AI) → result → share/print bez dead-endów.

**M1.3 Wybór trybów w EventHub/Settings.**
- Operator włącza/wyłącza tryby per-event; ekran gościa pokazuje tylko włączone.
- Accept: zmiana w settings zmienia dostępne tryby u gościa.

---

### M2 — KIOSK + MONETYZACJA

**M2.1 Kiosk lockdown + attract screen (iOS).**
- **Guided Access** flow dla 1 iPada: instrukcja/ekran „attract/idle" (branding, „Tap to start"), po sesji powrót do attract.
- **ASAM** (`UIAccessibility.requestGuidedAccessSession`) — wsparcie dla flot zarządzanych MDM (gdy allowlisted); graceful fallback gdy niedostępne.
- Zablokuj wyjście gościa do innych zakładek podczas aktywnej sesji eventu (kiosk = tylko ścieżka gościa).
- Accept: w trybie kiosk gość nie opuszcza ścieżki; po idle wraca attract screen.

**M2.2 StoreKit 2 subskrypcje + gating (iOS) + Stripe live (backend, TODO(human) na config).**
- StoreKit 2: produkty **Starter/Pro/Business**, **trial 14 dni**, `Transaction.currentEntitlements`,
  restore purchases, zarządzanie subskrypcją. Entitlement bramkuje funkcje premium (AI/360/print/white-label/multi-device).
- Zlikwiduj hardcoded „PRO" (`RootView.swift:364`) → realny tier z entitlementu + serwerowy `subscription-status`.
- `// TODO(human): utwórz produkty/ceny w App Store Connect; w Stripe (web/US) skonfiguruj produkty/coupon/webhook/env (runbook w ai-photobooth/TODO-HUMAN.md).`
- Accept: kupno w sandboxie nadaje entitlement; funkcje premium bramkowane; UI pokazuje realny plan.

---

### M3 — COMPLIANCE + DELIVERY

**M3.1 Zgoda RODO end-to-end (iOS + backend).**
- Disclaimer przed capture (jest) rozszerz o zgodę **AI/likeness** i **sharing/marketing** (opt-in, bez pre-check).
- **Retencja**: polityka usuwania zdjęć po evencie; **prawo do usunięcia** (guest przez link, operator w apce).
- Loguj zgodę (kiedy/zakres). Accept: bez zgody brak capture; usunięcie działa.

**M3.2 AI: detekcja twarzy/grup + retry/safety UX.**
- Wykryj liczbę twarzy (Vision); przy grupach komunikuj ograniczenie (single-face) i oferuj fallback/retry.
- Spójny UX czekania ~10s + obsługa safety_block/timeout (typed). Accept: grupowe zdjęcie nie kończy się cichym błędem.

**M3.3 Email white-label + guest event gallery.**
- Przekaż szablony operatora (subject/body/sender/branding) do `sendEmail` i wyślij je realnie (backend `/api/photos/{id}/email`).
- **Guest event gallery `/e/<slug>`** (backend route + strona) zamiast tylko `/p/<photoId>`; QR/share może wskazywać album eventu.
- Accept: e-mail przychodzi z brandingiem operatora; `/e/<slug>` pokazuje album eventu.

---

### M4 — POLISH + LAUNCH GATE

**M4.1 Onboarding operatora + szablony eventów.** First-run setup (branding, tryby, sharing); szablony Wedding/Birthday/Brand
prefillują settings. Accept: nowy operator stawia event w <5 min.

**M4.2 Observability + analytics.** Włącz Sentry (DSN — TODO(human)); structured logs w backendzie; per-event metryki
(liczba zdjęć, share rate) dla operatora. Shared rate-limit (Upstash/Redis) zamiast in-memory (TODO(human) na infra).

**M4.3 Audyt końcowy.** Przejdź §6 checklisty Apple z FINISH-PLAN; HIG/a11y/safe-area na iPad+iPhone; ukryj `/video`
virtual-background mock w prod; permisje Info.plist + Privacy Manifest kompletne. Accept: cała Definition of Done (§9 FINISH-PLAN) zielona.

---

## 5. STANDARDY JAKOŚCI (egzekwuj wszędzie)

- **iOS HIG:** clarity/deference/depth; jeden primary action/ekran w strefie kciuka; touch ≥44pt; safe-area (`env(safe-area-inset-*)`); Dynamic Type; VoiceOver labels; SF Symbols; native shutter/sheets/segmented; spring iOS (`cubic-bezier(0.32,0.72,0,1)`); Reduce Motion respektowany.
- **Backend:** typed errors, walidacja wejścia, idempotencja, brak surowych komunikatów do klienta, brak widocznych mocków w prod.
- **Bez slopu:** zero emoji jako ikon, zero generycznych gradientów, spójne radiusy (28–32pt karty), jeden akcent (token `violet`=niebieski).
- **Copy:** sentence case, konkret, aktywne czasowniki; błędy mówią co i jak naprawić.

## 6. TWARDE OGRANICZENIA — NIE WOLNO

- Zmieniać logiki biznesowej/route paths/nazw plików/kontraktów API tam, gdzie zadanie tego nie wymaga.
- Usuwać działających funkcji/trybów/kanałów share.
- Wpisywać sekretów/danych billingowych — zostaw `TODO(human)` z dokładną instrukcją.
- Zostawiać przełącznika Settings bez efektu oznaczonego jako „available".
- Wprowadzać light theme (zostań przy Apple-dark) ani regresji a11y/safe-area.
- Łamać build/test/lint w którymkolwiek repo.

## 7. NA KONIEC (handoff)

- Zaktualizuj `docs/PROGRESS.md`: stan każdego milestone'u, lista wszystkich `TODO(human)` (billing Gemini, App Store Connect, Stripe live config, Sentry DSN, infra rate-limit, decyzja monetyzacji 3.1.3c).
- Podsumuj before/after per ekran + co zostało do launchu.
- Potwierdź Definition of Done z `docs/FINISH-PLAN.md` §9 — zaznacz co spełnione, co czeka na człowieka.

---

### Skrót priorytetów (gdyby zabrakło czasu)
1. M0 (odblokowanie + prawda Settings) — bez tego apka „kłamie" i nie działa.
2. M1 (green screen + multi-capture) — table-stakes rynku.
3. M2 (kiosk + StoreKit) — żeby dało się używać na evencie i pobierać opłaty.
4. M3/M4 — compliance, delivery, polish, launch gate.
