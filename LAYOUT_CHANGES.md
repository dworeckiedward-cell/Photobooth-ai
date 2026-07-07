# Boothify 360 — LAYOUT_CHANGES: przebudowa kompozycji (bieg v3)

Nie reskin — przebudowa KOMPOZYCJI każdego ekranu wg zasad §2 briefu
(oddech / lekkie panele / jedna dominanta / hierarchia / akcja świeci /
chrome minimalny). Funkcja i routing bez zmian. Gate 54/54 zielony po
każdym ekranie. Commity: `474fd6d` → `e2c5e80` + stany.

## Bramka layoutu (nowe narzędzie)
`Photobooth-aiTests/LayoutSnapshotTests.swift` — **opt-in** harness
(`TEST_RUNNER_SNAPSHOT_DIR=… xcodebuild test -only-testing:…LayoutSnapshotTests`),
renderuje KAŻDY ekran do PNG w realnym oknie (UIWindow + drawHierarchy) z
wstrzykniętym stanem (eventy, joby processing/completed, link QR). Dzięki
temu kompozycję ekranów siedzących za backendem (hub, processing, result)
zweryfikowano zrzutami, nie tylko landing. Skip bez env — snapshoty nigdy
nie dzielą procesu z suite'ami silnika renderu (tło AVFoundation psuło
pamięć hosta testów — stąd opt-in).

## Per ekran — choroba → lek

### Home — BENTO (nadpisuje landing poniżej; kierunek od operatora, mockup HTML)
Kompozycja bento wg dostarczonego referensu: **powitanie + amber avatar**
(nagłówek nav ukryty — designed header), **świecąca karta „Start a new
session"** (fioletowo-tintowane szkło + amber ikona i glow; tap rozwija
inline strefę tworzenia: input + chipy szablonów + amber CTA — funkcja
createEvent nietknięta), **kafel „YOUR BOOTH"** (zdjęcie budki, status
Ready·idle / Rendering z kropką), **dwa staty** (spins captured, %
delivered — z lokalnych jobów; „—" zanim są dane), **wiersz „LATEST
EVENT"** ze SPINS (routing do huba jak dotąd). Pozostałe eventy przez
zakładkę Events (bento pokazuje tylko najnowszy — świadomie). Paleta
przełożona na nasz język: amber = akcent (mockup był mono-fioletowy).
Pułapka naprawiona w locie: `scaledToFill` zdjęcia budki rozpychał
kolumnę statów — obraz jako overlay na `Color.clear`.

### Landing (wzorzec-złoto, `474fd6d` — historyczny, zastąpiony przez BENTO)
- **Było:** pełnoszerokościowy box badge'a; cegła „NEW 360 EVENT" (label +
  input + chipy + CTA w jednym szkle) zżerająca pół ekranu; „Start session"
  wyprane biało-szare; osierocony empty-state z ikoną.
- **Jest:** pływający chip „360 mode · BETA"; hero-tytuł łamany w dwie
  linie; input jako WŁASNE cienkie szkło; chipy pływają na atmosferze;
  **CTA = amber kapsuła z glow** (jedyna dominanta; glow gaśnie przy
  disabled); wiersze eventów odchudzone (thumb 40 pt, slim padding);
  empty-state = dwulinijkowy szept bez ikony.

### Attract (`2edba90`)
- **Było:** dominantą była nazwa eventu; wezwanie do startu jako średni pill.
- **Jest:** brand operatora + nazwa cicho przy górnej krawędzi; środek trzyma
  **ogromne „Tap to start" (58 pt heavy + amber glow)** — czyta się z 3 m
  (świadomy holdout skali typograficznej, jak countdown); dół: pill „poprzednie
  wideo się kończy", mała amber ikona tapnięcia, niewidzialne „Boothify".
  Podtytuł przestał dublować nagłówek („Twoje wideo 360 za kilka chwil").

### Recording — świadomie zostawiony
Scena już spełnia §2: tłem jest live kamera, countdown 220 pt to dominanta,
kontrolki operatora znikają w kiosku. Dotykanie = ryzyko bez zysku.

### Processing (`60d532d`)
- **Było:** tip-bar (szkło) + cegła listy 6 kroków — ekran zapełniony statusami.
- **Jest:** **pierścień 220 pt z miękkim glow = jedyny hero ruchu**; kroki →
  cichy rząd 6 kropek; tip → pływająca linijka tekstu bez karty; oddech przez
  Spacery, treść max 560 pt. Failed: pełna kompozycja retry/back zostaje.
  Zdublowane radiale ambientu usunięte.

### Result + QR (`5e5b92b`)
- **Było:** ściana 4 równorzędnych rzędów (biały Share-bar, 4 kafle, „New
  take", 2 przyciski); QR schowany za kaflem; chipy metadanych w niebieskim.
- **Jest:** hierarchia **wideo → QR-hero → szepty**: inline skanowalny QR na
  lekkiej szklanej karcie z glow 0.4 („Pokaż na cały ekran" → istniejący
  sheet; placeholder z progressem zanim link będzie); metadane = jedna
  wyciszona linijka; akcje Share/SMS/Kopiuj/Zapisz = mały cichy rząd; **„Nowe
  ujęcie" usunięte jako duplikat** („Back to event" prowadzi w to samo
  miejsce — deduplikacja kontrolki, nie zmiana routingu); retry uploadu
  niebieski → amber.

### Event Hub (`38ee66c`)
- **Było:** ściana cegieł: kiosk-box, niebieski Cloud-panel wysoko, brick
  nagrań z fałszywymi „Open slot", 3 pudełka statystyk, ciężki share-box.
- **Jest:** foto-karta „Start session" pozostaje JEDYNĄ dominantą; kiosk =
  cienki szklany wiersz; nagrania pływają pod eyebrow (bez wrappera i bez
  fałszywych slotów); statystyki = **jedna przewiewna linia liczb z
  hairline'ami** (bez pudełek); share odchudzony; Cloud-panel zjeżdża na dół
  jako cichy detal operacyjny (liczniki bez boxów, amber zamiast niebieskiego).
  Perf-banner: bez zmian — pojawia się tylko gdy trzeba (już był cichy).

### Settings (`e2c5e80`) — hub eventu + zakładka aplikacji
- **Było:** czarny generic inset-List bez atmosfery, ikony NIEBIESKIE,
  „AVAILABLE" przy każdym wierszu, tożsamość na niebieskim klocku.
- **Jest:** oba ekrany przebudowane na ScrollView + **`SettingsSectionCard`**
  (nowy centralny komponent: eyebrow + cienki szklany panel) na atmosferze;
  ikony **amber**; badge tylko dla demo/beta (oba amber) — „AVAILABLE" to
  norma, nie news; tożsamość = lekkie szkło z amber aperturą; profil,
  subskrypcja (paid badge), ComingSoon, About — na języku v2.

### Stany (przekrojowo, ostatni commit)
- `BoothifyEmptyState` (hub „Event not found", result „job not found", cloud):
  z osieroconej ikony na środku → **skomponowane, leading-aligned oświadczenie
  na lekkim szkle** z amber siodełkiem ikony.
- `AppEmptyState` → szkło; `AppLoadingState` spinner → amber.
- Offline (result „Queued — offline", attract pill) i error (processing failed)
  były już skomponowane w poprzednich biegach — bez zmian.

## Palette-drift naprawiony (niebieski → koniec ery)
Źródło dryfu: token `BoothifyTheme.violet` był dosłownie **blue-500**.
1. **Centralnie:** token przetintowany na prawdziwy violet-500 (rodzina
   atmosfery) — jedna linia odbłękitnia całą apkę: login, paywall, kalendarz,
   kropki PIN, profil taba, globalny tint, kartę demo na Result.
2. **Amber tam, gdzie brief żąda:** ikony SettingsRow i globalSettingsRow,
   nagłówek Quick Setup, badge beta, tożsamość, profile-initial, paid-badge
   subskrypcji, toggles/ikony w formularzach (SettingsMVPViews,
   SettingsDetailViews), CloudStatusPanel (nagłówek, licznik uploading,
   progress-bar, refresh), chipy metadanych Result (→ jedna linijka), retry
   uploadu, StatTile „Processing", spinner AppLoadingState.
Fiolet pozostaje CICHYM wsparciem (mesh, dekoracje); amber = jedyny akcent
interakcji.

## Dodane do design systemu
- `AmberCTAButtonStyle` (Theme.swift) — świecąca akcja ekranu; parować z
  `.glowAccent()`, jedna na ekran.
- `SettingsSectionCard` (DesignSystem.swift) — szklana sekcja ustawień.
- `LayoutSnapshotTests` — bramka kompozycji (opt-in).

## Świadomie zostawione
- Recording (jak wyżej) i pill-nawigacja (wzorzec jakości — nietknięta).
- Foto hero-card w hubie — już była dominantą z hierarchią na obrazie.
- Tło = gładki mesh (brief §5): bogatsze tła to NIE ten bieg; hook
  `assetName` czeka.
- Sheety systemowe / natywne kontrolki formularzy.

## NEEDS-DEVICE
Layout zweryfikowany zrzutami we wszystkich stanach — na urządzeniu zostaje
wyłącznie „feel": materiał szkła na OLED, intensywność glow za tekstem
attract (58 pt + glow — banding?), czytelność „Tap to start" z 3 m w świetle
sali, skanowalność inline QR 108 pt z ręki gościa (jak źle — QR sheet jest
zawsze o tap dalej), Reduce Transparency na sprzęcie.
