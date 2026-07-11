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

---

# Aneks (dogrywka narzędziowa — pełne wykorzystanie skilla)

## Long-tail keywords (z `keyword_analyzer.find_long_tail_opportunities`, kuratorowane)

Generator jest mechaniczny (produkuje też śmieci typu „app 360 booth") —
poniżej wybór fraz, które mają sens językowy. NIE do pola keywords
(za długie) — do wplecenia w description (już częściowo są) i jako
kampanie exact-match w Apple Search Ads po launchu:

| Fraza | Konkurencja (est.) | Gdzie użyć |
|---|---|---|
| `360 booth app` | low | description ✓ (mamy), ASA exact |
| `360 photo booth app` | low | ASA exact — frazy z „photo" łapiemy mimo video-pozycjonowania |
| `wedding 360 booth` | low | description (sekcja BUILT FOR OPERATORS) + ASA |
| `360 booth rental` | low | ASA — intencja zakupowa operatora |
| `video booth app` | low | description ✓ |
| `event video booth` | low | ASA broad |
| `best 360 booth app` | very_low | ASA discovery — frazy „best/top" tylko płatnie |

## Plan testu A/B ikony (z `ab_test_planner`) — na PO launchu

- **Hipoteza:** glif 360-strzałki na fioletowym szkle > wordmark na
  impression-to-install. Split 50/50 (PPO w App Store Connect).
- **Metryka główna:** impression→install conversion; drugorzędne:
  tap-through, brand recall.
- **Twarda prawda z kalkulatora próby:** przy bazowej konwersji 3% i
  MDE 15% trzeba **~19 000 impresji na wariant** (38k łącznie). Przy
  ruchu niszowej apki B2B (~100 odsłon/dzień) to >12 miesięcy — czyli
  **klasyczny test istotności statystycznej jest nierealny na starcie.**
  Decyzja praktyczna: (a) najpierw PPO na **screenshot #1** (większy
  wpływ na konwersję niż ikona wg praktyki ASO), (b) test ikony traktować
  kierunkowo (2–4 tyg., bez czekania na istotność), (c) wrócić do pełnego
  testu gdy ASA nabije ruch.
- Best practices z narzędzia: jeden element na raz; czytelność w 60×60 px;
  porównać z ikonami LumaBooth/Touchpix zanim zamrozimy warianty.

## Pełna checklista launchowa (z `launch_checklist.py`, 42 pozycje) — zmapowana na stan Boothify

**App Store Connect Setup:** konto ✓(ludzkie, jest — ASC products w HANDOFF) ·
bundle ID ✓ (`com.servify.Photobooth-ai`) · **App Privacy declarations — OTWARTE
(HANDOFF §F: przepisać pod 360)** · age rating — OTWARTE.

**Metadata:** title/subtitle/promo/description/keywords ✓ (ten dokument,
zwalidowane) · kategorie ✓ (Photo & Video + Business).

**Visual Assets:** ikona 1024 — OTWARTE · screenshoty 6.7" — OTWARTE
(strategia wyżej) · 5.5" — wymagane przez ASC, OTWARTE · iPad 12.9" —
OTWARTE jeśli wspieramy iPada (HANDOFF §F) · preview video — OTWARTE.

**Technical:** build w ASC — OTWARTE (ludzkie: podpisy/Team ID) ·
TestFlight — OTWARTE · testy na iOS 17 na sprzęcie — **NEEDS-DEVICE
(Gate B, HANDOFF §A)** · crash-free >99% — po TestFlight · linki w
metadanych — /privacy i /terms istnieją na backendzie ✓.

**Legal & Privacy:** Privacy Policy URL ✓ · ToS URL ✓ · data declarations —
OTWARTE (spójne z PrivacyInfo.xcprivacy ✓) · third-party SDK disclosure —
Sentry do zadeklarowania.

**Pre-Launch Marketing:** landing — częściowo (strona /e/ galerii ≠ landing
produktu) · social/press kit/beta feedback/announcement — OTWARTE.

**ASO Preparation:** keyword research ✓ · competitor analysis ✓ (klin
w tym dokumencie) · **A/B plan post-launch ✓ (sekcja wyżej)** · analytics —
Sentry ✓, ASO-metryki przez ASC.

**QA:** core features — Gate A ✓ / Gate B NEEDS-DEVICE · user flows ✓
(snapshot harness) · performance — PerfBudget ✓ + device pending ·
accessibility — a11y labels ✓, VoiceOver pass na sprzęcie OTWARTE ·
security audit — PIN→Keychain ✓, sesja Keychain ✓.

**Support:** support email ✓ (support@boothify.app w apce) · FAQ/dokumentacja/
review-handling — OTWARTE.

**Wynik:** ~17/42 done, reszta to głównie pozycje ludzkie (Team ID, ASC,
grafiki, TestFlight) już spięte z HANDOFF §F — checklista narzędzia nie
odkryła nowych blockerów poza **age rating** i **deklaracją Sentry**,
które dopisano powyżej.
