# Boothify — App Store Metadata (ASO package)

Wygenerowane skillem `app-store-optimization`; wszystkie limity znaków
zwalidowane narzędziem `metadata_optimizer.validate_character_limits`
(EN i DE: zero errors/warnings, wykorzystanie pól 83–100%).
Pozycjonowanie: **narzędzie B2B dla operatorów eventowych** (nie consumer
selfie-app) — kategoria Photo & Video, target: wypożyczalnie fotobudek,
DJ-e/eventówki, agencje ślubne i korporacyjne.

## Strategia słów kluczowych

Oś: „360 booth" (kategoria sprzętu, którą operatorzy znają) + intencje
zakupowe operatora (booth *app*, rental, kiosk) + momenty użycia
(wedding, party, event). Konkurenci (LumaBooth, Touchpix, SpinStudio)
rankują na „photo booth" — bierzemy „photobooth/fotobox" jako keyword,
ale tytuł/subtitle różnicujemy na **video** (ich słabiej broniona flanka).
Zasady pola keywords zachowane: bez spacji, bez duplikatów, bez plurali,
bez słów już obecnych w tytule/subtitle (Apple indeksuje je osobno).

---

## 🇺🇸 English (US) — primary

| Pole | Wartość | Znaki |
|---|---|---|
| **Title** (30) | `Boothify: 360 Video Booth` | 25/30 |
| **Subtitle** (30) | `Spin, render & share via QR` | 27/30 |
| **Keywords** (100) | `360,booth,spin,slowmo,event,wedding,videobooth,photobooth,kiosk,party,qr,rental,dj,videofx` | 90/100 |
| **Promotional Text** (170) | `Run a 360 booth solo: record spins, get cinematic slow-mo rendered on-device in seconds, and hand guests their video by QR before they leave the platform.` | 154/170 |

### Description (EN)

```
Boothify turns an iPhone or iPad on a 360 platform into a complete video
booth — capture, cinematic rendering, and guest delivery, all on one
device. No laptop, no export queue, no second operator.

RECORD THE SPIN
• Guided countdown and on-screen cues for guests
• High-frame-rate capture for true slow motion — never faked
• Stabilization presets that smooth platform vibration
• Kiosk mode: hand the device to guests, locked to the booth

RENDER ON-DEVICE, IN SECONDS
• Cinematic motion templates: hero slow-mo, reverse bounce, loop promo
• Segment timeline editor: speed ramps, reverse, slow-mo per slice
• Your client's logo composited onto every video
• Soundtrack, intro and outro clips

DELIVER BEFORE THE SONG ENDS
• QR code on screen the moment the spin ends — guests scan and go
• Email, SMS and share-sheet delivery built in
• Works on venue Wi-Fi that drops: videos queue and send when back online
• Every clip stays in the event hub, organized by date

BUILT FOR OPERATORS
• Per-event settings: branding, consent forms, surveys, lock PIN
• Run back-to-back guests while previous videos finish in the background
• Lead capture and CSV export for corporate activations

Boothify Pro unlocks white-label branding and unlimited events.

Made for photo booth rental companies, DJs, wedding and corporate event
teams. Requires a 360 booth platform (any rotating arm works) and
iOS 17 or later.
```

### What's New (template pierwszego release)

```
Welcome to Boothify 1.0 — the 360 video booth that fits in your pocket.
• Record, render and deliver 360 spins from one device
• Cinematic slow-mo templates with real high-frame-rate capture
• Instant QR delivery, with offline queueing for flaky venue Wi-Fi
• Kiosk mode for self-serve guests
```

---

## 🇩🇪 Deutsch — druga lokalizacja (rynek DACH; polski celowo pominięty)

| Pole | Wartość | Znaki |
|---|---|---|
| **Title** (30) | `Boothify: 360 Video Booth` | 25/30 (nazwa + kategoria funkcjonują po niemiecku) |
| **Subtitle** (30) | `Drehen, rendern, per QR teilen` | 30/30 |
| **Keywords** (100) | `360,booth,spin,zeitlupe,event,hochzeit,videobooth,fotobox,kiosk,party,qr,verleih,dj,feier` | 89/100 |
| **Promotional Text** (170) | `360-Booth solo betreiben: Spins aufnehmen, Slow-Motion direkt auf dem Gerät rendern und Gästen ihr Video per QR übergeben — noch auf der Plattform.` | ~146/170 |

Uwaga rynkowa: w DACH operatorzy szukają „Fotobox" (nie „photo booth") —
stąd `fotobox` i `verleih` (wynajem) w keywords; „Videobox" ma za mały
wolumen, lepiej broni się `videobooth`.

### Beschreibung (DE) — skrót do przetłumaczenia w całości przy submissji
Struktura 1:1 z EN (AUFNEHMEN → AUF DEM GERÄT RENDERN → LIEFERN, BEVOR
DER SONG ENDET → FÜR BETREIBER GEBAUT). Pełne tłumaczenie zrobić z
native-review przed publikacją (zasada skilla: nie machine-translation).

---

## Zrzuty ekranu — strategia konwersji (pierwsze 3 decydują)

1. **Hero:** telefon na ramieniu 360 + kadr z aplikacji „Start a new
   session" — caption: *„Your entire 360 booth. One device."*
2. **Wow dostawy:** ekran Result z podglądem wideo + kafel QR — caption:
   *„Guests scan. Video's theirs. 15 seconds."*
3. **Render:** ekran Processing (ring 33%) — caption: *„Cinematic slow-mo
   rendered on-device."*
4. Kiosk attract („Tap to start" z 3 metrów), 5. Ustawienia brandingu
   (white-label), 6. Event hub (back-to-back guests).
App Preview video: 20 s pętla spin → render → skan QR (bez dźwięku
lektora, napisy).

## Kategoria i pozycjonowanie
- **Primary:** Photo & Video. **Secondary:** Business (operatorski charakter).
- Luka konkurencyjna: LumaBooth/Touchpix pozycjonują się photo-first i
  wymagają cięższego setupu; SpinStudio jest hardware-bound. Nasz klin:
  **„render on-device + QR zanim gość zejdzie z platformy"** — to zdanie
  ma być wszędzie (subtitle, promo text, screenshot #2).

## Przed submissją (launch checklist — skrót)
- [ ] Pełne DE tłumaczenie opisu + native review
- [ ] 6 zrzutów 6.9" + 6.5" (+ iPad 13" jeśli wspieramy — HANDOFF §F)
- [ ] App Preview 15–30 s
- [ ] App Privacy label przepisany pod 360 (HANDOFF §F — wciąż otwarte)
- [ ] Promotional Text można podmieniać BEZ release'u — używać sezonowo
      (wedding season maj–wrzesień: promo z „wedding" na przedzie)
- [ ] Po 2 tygodniach: A/B ikony (PPO w App Store Connect)
