# Boothify 360 — UI CHANGES V2: Atmospheric Glass

Fundament `36cc758` → kaskada `c4ce8ff`. Gate 54/54 zielony po każdym kroku.
Język opisany w `DESIGN_SYSTEM.md` (źródło prawdy).

## Zmienione

**Fundament (centralnie — zero per-ekran hardkodów):**
- `AtmosphericGlass.swift`: `AtmosphericBackground` (deep violet/indigo mesh +
  amber-szept + scrim; hook `assetName` na branding operatora), `GlassSurface`
  (ultraThinMaterial-dark + rim + radius + cień; **Reduce Transparency →
  solid bgElevated**), `GlowAccent`.
- Tokeny: `bgDeep`, `bgElevated`, `indigoGlow`; `BoothifyType.hero`.
- **Kaskada centralna**: `AppCard` + legacy `Surface` renderują jako szkło →
  wszystkie settings-karty, panele, wiersze przeszły na nowy język bez
  dotykania ich plików.

**Per ekran:**
- **RootView**: `AtmosphericBackground` w ZStacku NavigationStacka — atmosfera
  pod WSZYSTKIMI tabami i pushowanymi ekranami; tab bar → kompaktowy
  icon-only pill (aktywny tab w szklanym siodełku, tytuły jako a11y labels,
  44 pt+ targets).
- **Attract**: atmosfera + `hero` typografia + glow 0.7 na CTA.
- **Recording**: kamera pozostaje tłem (słusznie); glow na ringu przycisku
  nagrywania (0.55 idle / 0.25 rec) + amber shadow na cue „START!".
- **Processing**: atmosfera; karty tipów i kroków → szkło.
- **Result**: atmosfera; kafle akcji + „New take" → szkło; **QR na szklanej
  karcie hero-radius z glow 0.45** (moment wow dostawy).
- **Hub / Landing**: atmosfera; create-card + wiersze eventów → szkło; nagłówek
  landingu → `hero`.

## Świadomie zostawione
- **Recording bez AtmosphericBackground** — tłem gościa jest LIVE kamera;
  nakładanie mesh-u byłoby dekoracją kosztem funkcji.
- **Formularze ustawień (List/Form)** — karty wewnątrz przeszły na szkło przez
  kaskadę; tło List pozostało ciemne solidne (gęste formularze czytają się
  lepiej na spokojnym tle; atmosfera pod spodem prześwituje przez nav-stack).
- **Sheety systemowe** (share/consent/alerty) — natywne, bez restylingu.
- Paleta i routing nietknięte poza rolami opisanymi w DESIGN_SYSTEM.

## Weryfikacja w symulatorze (zrzut)
Landing potwierdzony screenshotem: mesh + scrim, hero-typografia, szklana
karta, pill-nav z ikonami. Po drodze złapany i naprawiony **stale-build trap**
(alfabetyczny wybór DerivedData podstawił czerwcową binarkę — dyscyplina
screenshotów zadziałała). Uwaga: przy pierwszym launchu dialog uprawnień
powiadomień (istniejący NotificationManager) zasłania środek — zachowanie
sprzed tego biegu, nie regresja.

## NEEDS-DEVICE (symulator ≠ materiał)
- Realny wygląd `ultraThinMaterial` (głębia blur na panelu OLED, nie sRGB sim),
  rim highlight i cienie szkła.
- Czytelność attract/countdown/QR **z 3 metrów** na iPadzie w świetle sali.
- Glow amber na czerni panelu (banding? intensywność?).
- Feel pill-nav pod kciukiem; reveal beat na realnym wideo; scrim vs realne
  jasne sceny kamery na Result.
- Reduce Transparency na urządzeniu (fallback solid — wygląd do oceny).

## Tokeny/komponenty dodane (pełna lista)
`AtmosphericBackground` · `GlassSurface`/`.glassSurface` · `GlowAccent`/
`.glowAccent` · `bgDeep` · `bgElevated` · `indigoGlow` · `BoothifyType.hero`.
(Z biegu v1: `BoothifyTheme.recording`.)
