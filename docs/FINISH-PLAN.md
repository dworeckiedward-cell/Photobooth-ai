# Boothify — Plan dokończenia do płatnego produktu (v1 launch)

> Cel: doprowadzić Boothify (natywna apka iOS/iPadOS, SwiftUI + backend Next.js na Vercelu)
> do poziomu **płatnego produktu rynkowego dla fotobudkowiczów**, na równi z liderem
> kategorii **LumaBooth** — z naciskiem na standardy Apple (HIG, App Review, kiosk),
> wiarygodność (koniec z „martwymi" przełącznikami) i monetyzację.
>
> Dokument powstał z: (1) audytu kodu obu repo, (2) deep-researchu rynku/standardów.
> Towarzyszy mu `docs/EXECUTION-PROMPT.md` — długi prompt wykonawczy dla agenta.

---

## 0. North star

Operator (firma fotobudkowa) kupuje subskrypcję, w 5 minut konfiguruje event,
stawia iPada w trybie kiosk, a gość: podchodzi → robi zdjęcie/GIF/wideo/360 →
(opcjonalnie) AI-portret → dostaje wynik → udostępnia (e-mail/SMS/QR/AirDrop/WhatsApp)
lub drukuje. Wszystko działa offline-first, wygląda jak first-party Apple, i jest
zgodne z RODO. Operator ufa softwarowi na tyle, by za niego **płacić co miesiąc**.

---

## 1. Stan obecny (z audytu)

### Działa produkcyjnie (nie ruszać bez powodu)
- **Rdzeń foto:** capture (AVFoundation) → upload → **Gemini generate** → poll → result → share.
- **Sharing:** Save (PHPhotoLibrary), Email (`/api/photos/{id}/email`, Resend), SMS (Twilio bezpośrednio lub backend), WhatsApp (`wa.me`), QR (CoreImage), **AirPrint** (single/2-strip/4-strip/double).
- **360 Booth:** realne nagranie + render on-device (FFmpegKit) + upload signed→PUT→confirm + retry queue.
- **Auth:** Apple Sign In + Supabase, Keychain, 401→refresh (gate OFF w Debug — patrz §6).
- **Offline/crash:** `PhotoUploadQueue`, `Booth360UploadQueue`, `CrashRestoreManager`, `NetworkMonitor`.
- **Settings z realnym efektem:** Lock PIN, Brand Overlay, Virtual Attendant (TTS), Disclaimer (zgoda), Survey, Delivery Status, album shareMode, SMS template+Twilio, Print enabled/autoPrint, AI Portraits enabledStyles/order.
- **Backend:** 34 realne route'y z auth/validacją/rate-limit; Stripe spięty end-to-end (kod); pipeline Gemini z retry/safety/watermark/quota-logiem.

### Mock / „coming soon" / martwe (DO NAPRAWY — to największe ryzyko wiarygodności)
- **Martwe sekcje Settings oznaczone jako „available"** (kłamią o funkcjonalności):
  - **Capture** — countdown zahardkodowany na 3 (`CameraScreen.swift:548`), jakość JPEG 0.85, liczba zdjęć, GIF w pipeline — nic nie konsumowane.
  - **Camera** — `mirrorSelfie` ignorowany (zawsze `true`), zoom/flash/rotacja nieczytane.
  - **Effects** — beautify/grain/vignette/filter — całkowicie martwe.
  - **Gallery/Slideshow settings** — nieczytane, nie w Hubie.
- **Background Removal / green screen** — tylko „Demo", brak realnego maskowania (`SettingsMVPViews.swift:258,314,354,385`).
- **AI360 overlays + soundtrack + auto-start** — `ComingSoonRow`, pola `// placeholder`.
- **Email templates** (subject/body/sender/branding) — ustawiane, ale **nigdy nie wysyłane** (backend ma własny szablon).
- **„PRO" badge** zahardkodowany (`RootView.swift:364`) — brak StoreKit/subskrypcji/gatingu.
- **Calendar sync** — „coming soon" locked (`EventsCalendarView.swift:413`).
- **Guest event gallery** — share wskazuje na pojedyncze `/p/<photoId>`, brak `/e/<slug>`.
- **/video virtual-background (web)** — widoczny mock (Kling/RunPod nieobecne) — ukryć w prod.
- **Backend:** generacja **zablokowana** Gemini 429 (free-tier limit 0 → billing); race condition na `max_photos` (`generate/route.ts:156`); quota „fail-open"; Google 429 mapowane na HTTP 500; rate-limit in-memory; brak observability; brak maili dunning (`stripe/webhook:277`).

---

## 2. Cel rynkowy (z researchu — baseline LumaBooth)

**Potwierdzone table-stakes** (źródła first-party LumaSoft):
- **Tryby capture w jednej apce:** photo, GIF, boomerang, **video**, **360**, **green screen (chroma key)**, **AI background removal**.
- **Multi-channel sharing + offline queue:** email, SMS, Instagram, QR, AirDrop, WhatsApp.
- **Guest data capture:** surveys, feedback, **disclaimers (zgoda)**.
- **Cena referencyjna:** subskrypcja ~$18–20/mc, **2 urządzenia** w bazowym planie.

**Ograniczenia AI (potwierdzone):** portrety AI w kategorii wspierają **jedną twarz** —
brak grupowych (Booth.Events). Na evencie (grupy!) trzeba **wykrywać liczbę twarzy**,
jasno komunikować i mieć fallback.

**Apple billing (potwierdzone, zmienne w czasie):**
- 3.1.3(c) Enterprise exception — tylko **realna sprzedaż do organizacji**; self-serve consumer = **musi IAP**.
- US storefront: linki zewnętrzne **bez entitlementu** (po wyroku Epic v. Apple, 30.04.2025) — pod apelacją.
- Non-US: linki zewnętrzne tylko z **External Purchase Link Entitlement** (region-limited) albo zakaz.
- **Wniosek:** najbezpieczniej **StoreKit 2** dla self-serve; web/Stripe jako opcja tylko w US.

**RODO (potwierdzone):** zdjęcia gości = dane osobowe (też pośrednio: ubiór/tatuaże/tło);
przetwarzanie biometryczne do identyfikacji → Art. 9. Ekrany zgody/disclaimer obowiązkowe.

**Kiosk (kierunkowo):** Guided Access (1 iPad) + **ASAM** (Autonomous Single App Mode, flotа MDM).

---

## 3. Analiza luk → priorytety

| # | Luka | Waga | Dlaczego |
|---|------|------|----------|
| G1 | Gemini billing (429) | **BLOCKER** | Bez tego produkt nie działa wcale |
| G2 | Stripe live + **StoreKit 2** | **BLOCKER** | Bez tego nikt nie zapłaci |
| G3 | Martwe Settings „available" | **Krytyczne** | Apka kłamie o funkcjach → utrata zaufania/refundy |
| G4 | Green screen / background removal | **Krytyczne** | Table-stakes LumaBooth; teraz „demo" |
| G5 | Kiosk lockdown (Guided Access + ASAM) | **Krytyczne** | Operacja bez nadzoru na evencie |
| G6 | Multi-capture przez AI + paski wydruku | **Wysokie** | GIF/SlowMo dziś dead-end; brak photo-strip→AI |
| G7 | Email white-label (szablony faktycznie wysyłane) | **Wysokie** | Marketowy white-label |
| G8 | AI: detekcja twarzy/grup + retry/safety UX | **Wysokie** | Reliability na evencie |
| G9 | Zgoda RODO end-to-end + retencja | **Wysokie** | Legal gating |
| G10 | Onboarding operatora + szablony eventów | **Wysokie** | Trust = sprzedaż |
| G11 | AI360 overlays/soundtrack/auto-start | Średnie | Parytet 360 |
| G12 | Guest event gallery `/e/<slug>` | Średnie | Delivery UX |
| G13 | Observability + race-fix + 429→typed + rate-limit shared | Średnie | Produkcyjna higiena |
| G14 | Analytics produktowe + per-event metryki | Średnie | Wartość dla operatora |
| G15 | Calendar sync (EventKit/Google) | Niskie | Wygoda |
| G16 | APNs push | Niskie | Dziś local-only wystarcza |

---

## 4. Roadmapa w milestone'ach (sekwencja dla agenta)

> Każdy milestone = build zielony + weryfikacja w symulatorze + commit. Logika nietknięta
> tam, gdzie nie trzeba; zmiany prezentacji zawsze bezpieczne.

- **M0 — Odblokowanie i prawda (1 dzień)**
  - G1: doprowadzić generację do działania (billing po stronie usera; w kodzie: 429→typed error, komunikat w apce).
  - G3: **pogodzić Settings z rzeczywistością** — albo zaimplementować (countdown, liczba zdjęć, mirror, jakość), albo schować/oznaczyć „Coming soon" zamiast „available". Zero przełączników bez efektu.
  - G13 (część): race-fix `max_photos`, 429 Google → 429/503 typed, env validation na boot.

- **M1 — Capture parity (1–1.5 dnia)**
  - G4: realny **green screen / background removal** (Vision/CoreImage person segmentation on-device; tła per-event).
  - G6: **multi-capture → AI → share/print**: photo-strip, burst, boomerang/GIF flow przez pipeline, layouty pasków.
  - Tryby capture wybierane per-event (photo/GIF/boomerang/video/360/green-screen).

- **M2 — Kiosk + monetyzacja (1–1.5 dnia)**
  - G5: **Guided Access** flow (attract screen, lock, single-event), wsparcie **ASAM** dla flot; „attract/idle" ekran.
  - G2: **StoreKit 2** subskrypcje (tiers + trial), gating funkcji premium, koniec hardcoded „PRO"; Stripe live jako ścieżka web (US).

- **M3 — Compliance + delivery (1 dzień)**
  - G9: zgoda RODO end-to-end (disclaimer przed capture, retencja, prawo do usunięcia), G8: detekcja twarzy/grup + retry/safety UX.
  - G7: email white-label (szablony przekazywane i wysyłane), G12: guest event gallery `/e/<slug>`.

- **M4 — Polish + launch gate (0.5–1 dzień)**
  - G10: onboarding operatora + szablony eventów (Wedding/Birthday/Brand).
  - G14: analytics per-event; G13: observability (Sentry DSN, structured logs), shared rate-limit.
  - Pełny audyt HIG/a11y/safe-area na iPad + iPhone; ukrycie `/video` mocka w prod; przejście launch-checklisty (§9).

(M5 opcjonalne/post-launch: AI360 overlays/soundtrack, calendar sync, APNs, real 360 video render.)

---

## 5. Monetyzacja (rekomendacja)

- **Self-serve App Store → StoreKit 2** (subskrypcje auto-renewable). To jedyna pewna ścieżka,
  bo sprzedaż do małych operatorów może być zaklasyfikowana jako „consumer/single-user".
- Tiers wzorowane na rynku (LumaBooth ~$18–20/mc, 2 urządzenia). Propozycja:
  - **Starter** — 1 urządzenie, foto+share, bez AI/360/print premium.
  - **Pro** — 2 urządzenia, wszystkie tryby capture + AI + print + white-label.
  - **Business** — flota/MDM/ASAM, branding głębszy, priorytet AI.
- **Trial 14 dni** (introductory offer). Gating przez entitlement (StoreKit) + serwerowy `subscription-status`.
- **Stripe (web)** — zostaw jako ścieżkę dla kontraktów org/US storefront; nie polegać na niej dla self-serve.
- „PRO" w UI musi odzwierciedlać **realny** entitlement, nie hardcode.

---

## 6. Checklist zgodności Apple (przed submitem)

- [ ] `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSMicrophoneUsageDescription` (wideo/360) — konkretne, prawdziwe opisy.
- [ ] `authGateEnabled` ON w Release (dziś OFF w Debug — `AppConfig.swift:19`).
- [ ] StoreKit 2 + Privacy Manifest (`PrivacyInfo.xcprivacy`) + App Privacy „Nutrition Label" (zdjęcia/e-mail/telefon gości).
- [ ] iPad-first: layout, orientacje, brak treści pod home-indicatorem/notch, multitasking sane.
- [ ] Accessibility: Dynamic Type, VoiceOver na ścieżce gościa i operatora, kontrast AA.
- [ ] Kiosk: Guided Access działa; ASAM zbudowane + allowlista (jeśli flota).
- [ ] UGC/zdjęcia osób + AI likeness: zgoda + moderacja treści; provenance label (rozważyć EU AI Act Art. 50, 08.2026).
- [ ] Brak widocznych mocków w produkcie (ukryć `/video` virtual-background).
- [ ] Subskrypcje: opis, przywracanie zakupów, link do regulaminu/prywatności, zarządzanie.

---

## 7. Prywatność / legal (consent)

- **Disclaimer przed capture** (jest — `DisclaimerSettingsView`): rozszerzyć o zgodę na AI/likeness i sharing/marketing.
- **Retencja:** polityka usuwania zdjęć po evencie; **prawo do usunięcia** (guest + operator).
- **Biometria/AI:** jeśli pipeline ekstrahuje geometrię twarzy do identyfikacji → Art. 9 (explicit consent). Sam restyle stylistyczny zwykle poza Art. 9 — potwierdzić technicznie.
- To **nie jest porada prawna** — operator powinien potwierdzić z prawnikiem dla swoich jurysdykcji.

---

## 8. Top ryzyka

1. **Apple billing klasyfikacja** — czy self-serve kwalifikuje się pod 3.1.3(c). Mitygacja: StoreKit 2 jako domyślne.
2. **Gemini koszt/limit** — race condition + fail-open quota → przepał. Mitygacja: advisory lock + twardy backstop budżetu.
3. **AI reliability na grupach** — single-face limit. Mitygacja: detekcja twarzy + jasny UX + fallback.
4. **Wiarygodność UI** — martwe przełączniki = recenzje/refundy. Mitygacja: M0 „prawda".
5. **RODO** — zdjęcia gości to dane osobowe. Mitygacja: consent end-to-end + retencja.
6. **Reguły Apple zmienne w czasie** — zweryfikować 3.1.1(a)/3.1.3(c) na dzień submitu.

---

## 9. Definition of Done (launch gate)

- [ ] Generacja AI działa end-to-end na realnym urządzeniu (po billingu); błędy typed + czytelne w UI.
- [ ] Zero przełączników Settings bez efektu; każda widoczna funkcja działa lub jasno „wkrótce".
- [ ] Tryby capture: photo/GIF/boomerang/video/360/green-screen — wszystkie realne i wybieralne per-event.
- [ ] Multi-capture → AI → share/print działa; layouty pasków drukują się poprawnie.
- [ ] Kiosk: Guided Access + attract screen; (flota) ASAM.
- [ ] StoreKit 2 subskrypcje + trial + gating; „PRO" = realny entitlement.
- [ ] Consent RODO + retencja + usuwanie; permisje i Privacy Manifest kompletne.
- [ ] HIG/a11y/safe-area OK na iPad + iPhone; brak mocków w prod.
- [ ] Build/test/lint zielone w obu repo; observability włączone; race/quota/429 naprawione.
- [ ] Onboarding + szablony eventów; delivery przez `/e/<slug>` gallery.

---

### Załączniki / źródła
- Audyt iOS i backend: w historii sesji (file_path:line w treści powyżej).
- Research (cytaty): LumaSoft `dslrbooth.com/lumabooth-photo-booth-app`, `support.lumasoft.co`;
  Booth.Events `help.booth.events/article/98-ai-portraits`; Apple `developer.apple.com/app-store/review/guidelines`;
  RODO `gdpr-info.eu` Art. 4/9; kiosk `simplemdm.com`. Reguły Apple i ceny — zweryfikować na dzień wdrożenia.
