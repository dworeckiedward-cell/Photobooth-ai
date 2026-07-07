# Boothify 360 — AUDIT_REPORT

Audyt read-only, przeprowadzony na REALNYM kodzie (4 równoległe śledztwa,
weryfikacja `plik:linia`). Zero zmian w kodzie — czysta diagnoza.
Data: 2026-07-07.

> **Uwaga wstępna (istotna):** `BOOTHIFY_360_BLUEPRINT.md` **NIE ISTNIEJE w repo**
> (`find … -iname "*blueprint*"` → brak). Blueprint jest gęsto cytowany w
> komentarzach kodu (`§7`, „Phase 3" itd.), ale sam dokument jest poza repo.
> Intencję odtworzono z `PROGRESS.md`, `DECISIONS_LOG.md`, `BACKEND_CONTRACT.md`,
> `HANDOFF.md`, `NEEDS_DEVICE.md` + realnego kodu. Każdy audyt vs „blueprint"
> to w praktyce audyt vs te dokumenty + kod.

---

# CZĘŚĆ A — AUDYT TECHNICZNY

## Tabela statusów

| # | Obszar | Status | Dowód | Komentarz |
|---|---|---|---|---|
| 1 | FFmpeg usunięty z SPM | **DONE** | `project.pbxproj:155-156, 489-506` — jedyny remote package to sentry-cocoa | Naprawdę usunięty. |
| 1 | `Booth360FFmpegRenderClient.swift` skasowany | **DONE** | plik nie istnieje; opisany jako usunięty w `Booth360NativeRenderClient.swift:12,177` | Gone. |
| 1 | Referencje ffmpeg w `*.swift` | **DEVIATED (kosmetyka)** | 8 plików wciąż nazywa FFmpeg w KOMENTARZACH: `Booth360.swift:101,161,323,329`, `Booth360NativeRenderClient.swift:12,177`, `SettingsMVPViews.swift:117,318`, `Booth360RecordingView.swift:504`, `EventSettings.swift:261`, `Booth360CloudUploader.swift:7`, `Booth360ResultView.swift:6`, `BoothifyAPI.swift:194` | Zero kodu ffmpeg. Komentarze aktywnie kłamią — `SettingsMVPViews.swift:117` mówi operatorowi że logo „baked in by the FFmpeg renderer (once the binary is wired)". Do wyczyszczenia. |
| 1 | Domyślny render client | **DONE (realny AVFoundation)** | `AppState.swift:482-491` → `Booth360NativeRenderClient.shared.runPipeline`; `Booth360ProcessingView.swift:80-85` `.task` → `startRender` | Nie passthrough, nie ffmpeg. `Booth360PassthroughRenderClient` (`Booth360.swift:332`) istnieje tylko jako fallback wewnątrz klienta API. |
| 2 | Realny pipeline AVMutableComposition + AssetWriter + VideoToolbox H.264 | **DONE (realny)** | `Booth360RenderEngine.swift:63` (composition), `:277-286` (AssetReader+VideoCompositionOutput), `:299` (AssetWriter mp4), `RenderSpec.swift:39-51` (H.264 High + bitrate/preset), pompa klatek `:363-388` z `autoreleasepool` | Prawdziwy reader→writer transcode, nie skrót `AVAssetExportSession`. Tylko H.264 (brak HEVC — spec nie wymaga). |
| 2 | Capture realny (nie fake timer) | **DONE (realny) — komentarze STALE** | `CameraController.swift:15-17` `AVCaptureMovieFileOutput`, `startRecording(to:)` `:298-322`; `Booth360RecordingView.swift:524-526,565,579` zapis realnego pliku | Timer `:535-545` napędza TYLKO licznik na ekranie + trigger końca, NIE fabrykuje pliku. **Ale** nagłówki `Booth360RecordingView.swift:7-9` i `Booth360.swift:79-80` wciąż twierdzą „mock/no-file timer, rawVideoLocalURL = nil" — **jawnie fałszywe**. Symulator degraduje do Mock. |
| 2 | Speed ramp (`scaleTimeRange`) + klauzula uczciwości slow-mo | **DONE (realny)** | clamp `MotionTemplates.swift:92-96` (`minHonestSpeed = min(outputFPS/captureFPS,1)`), `scaleTimeRange` w silniku `Booth360RenderEngine.swift:121-124,152-154`; breadcrumb clamp `Booth360NativeRenderClient.swift:81-86` | Nigdy nie udaje slow-mo ponad zarejestrowane klatki. Poprawna separacja (template emituje segmenty, silnik skaluje). |
| 2 | Reverse re-encode | **DONE (realny)** | `Booth360ReverseEncoder.swift:26-157` (chunked reader→writer, `chunkBuffers.reversed()` z nowym PTS, `autoreleasepool`) | Prawdziwe odwracanie klatek. Drobny smell: `:160-169` martwa linia `t.tx = … t.tx`. |
| 2 | Overlay compositing per-frame (CoreImage/GPU) | **DONE (realny)** | `Booth360RenderEngine.swift:319-338,367-381` (`CIImage.composited(over:)` + `CIContext().render` przez `AVAssetWriterInputPixelBufferAdaptor`); walidacja `OverlaySpec.swift:42-81` (odrzuca pełnoklatkowy/aspect-mismatch, realna próba alfy `CIAreaMinimum`) | Realny per-frame composite, nie tani post-overlay. Overlay statyczny (spec nie wymaga animowanego). |
| 2 | 120 fps capture | **REALNY KOD / NEEDS-DEVICE** | `CameraController.swift:189-234` `configureHighFrameRate(target:120)` (realna enumeracja formatów, brak cichego udawania), wołane `Booth360RecordingView.swift:456`, marker `:455` | Weryfikacja wymaga urządzenia. |
| 2 | 240 fps capture | **DEVIATED (martwy)** | `CameraController.swift:263-293` `configureSlowMotion()` ustawia 240fps, ale **brak call-site** w ścieżce nagrywania (podpięte tylko 120) | Zaimplementowane, ale niepodpięte — de facto uśpione. |
| 5 | iOS deployment target 17.0 | **DONE** | `project.pbxproj:264,322,422,443` — wszystkie 4 configi `IPHONEOS_DEPLOYMENT_TARGET = 17.0` | Spójne. Weryfikacja tylko kompilacyjna, brak dowodu runtime iOS 17 (`PROGRESS.md:34-36` sam to flaguje NEEDS-DEVICE). |
| 5 | Paywall gating sandbox-safe (fail-open) | **DONE** | `StoreManager.swift:66-69` `guard storeConfigured else { return true }`; `storeConfigured = !products.isEmpty` (`:103`); render-path nil-safe `Booth360NativeRenderClient.swift:66-67,96-97`; testy `Phase8HardeningTests.swift:53-70` | Operator NIGDY nie jest twardo zablokowany bez produktów ASC. Jednoznacznie dobrze zrobione. |
| 5 | Testy + gate.sh | **DONE (z zastrzeżeniem)** | `scripts/gate.sh:1-23` (build→test, `exit 1` przy error/FAILED; destination hardkodowany `iPhone 17 Pro:6`); 13 plików testów, ~55 metod `func test`; `LayoutSnapshotTests.swift:100-103` opt-in (`XCTSkipUnless … SNAPSHOT_DIR`) | Solidne pokrycie logiki (render, motion, overlay, stabilizacja, delivery, storage, decode, upload-queue, route, Phase-8). Ale to niemal wyłącznie testy white-box/Gate-A (symulator/syntetyk). Dowodzą matematyki, nie produktu. |
| 5 | Fazy 0–8 ukończone | **DONE (artefakty obecne)** | `PROGRESS.md:9,42,80,103,140,170,198,222,249` wszystkie „✅ GATE GREEN"; spot-check: pliki faz 3/4/8 istnieją. Drift nazewnictwa: `TriggerStateMachine` żyje w `RecordingTrigger.swift`, nie w osobnym pliku | Brak faz-widm. Ale „GATE GREEN" = „Gate A (symulator) green"; każda faza niesie nierozwiązany „Gate B → HANDOFF". |

## Backend (Część A.3)

| Punkt | Status | Dowód | Komentarz |
|---|---|---|---|
| `BACKEND_CONTRACT.md` opisuje realne `/api/booth360/*` | **DONE** | `BACKEND_CONTRACT.md:7-21` | Kontrakt uczciwy; flaguje że `/p/{id}` to strona PHOTO i NIE wolno jej używać dla 360. |
| `Booth360CloudUploader` sign→PUT→confirm | **DONE** | `Booth360CloudUploader.swift:86-99` (sign), `:113-133` (PUT), `:135-151` (confirm); ścieżki w `BoothifyAPI.swift:167-187,108-140,238-276,292-296` | Deferred-resolve „moat" realny: `publicShareURL` z odpowiedzi sign (`:107-111`) PRZED PUT. |
| **GAP #1 — persystentna historia klipów** | **DEVIATED (dok przecenia)** | GET kolekcji podpięty: `BoothifyAPI.listEventBooth360Jobs` → `GET /api/events/{slug}/booth360-jobs` (`BoothifyAPI.swift:317-322`), merge `AppState.hydrateJobs` (`AppState.swift:508-534`), wołane `Booth360EventHubView.swift:209`. **ALE** `AppState.booth360Jobs` to czysty in-memory `[UUID:Booth360Job]` BEZ persystencji dysk/UserDefaults (`AppState.swift:448`) | `BACKEND_CONTRACT.md:31-37` twierdzi „clip history now survives reinstall". **Półprawda:** przeżywają TYLKO klipy które dotarły na serwer (uploaded+confirmed) i TYLKO po ponownym wejściu w hub eventu. Klipy wyrenderowane-lokalnie-nie-wysłane i eventy nieodwiedzone → znikają po reinstalacji. Brak lokalnej galerii; dict czyszczony przy każdym starcie. |
| Ryzyko decode: `progress` bez default | **PARTIAL (ryzyko)** | `Booth360JobDTO.progress` to non-optional `Double` bez default (`APIModels.swift:102`); reszta pól optional (`:97-122`) | Jeśli backend pominie `progress` na dowolnym jobie → cały decode `listEventBooth360Jobs` rzuca i wpada w cichy catch → **milcząco gubi całą serwerową historię eventu** (nie crash, ale utrata danych). |
| Migracje Supabase 14/15 | **PARTIAL** | `BACKEND_CONTRACT.md:42-45`, `HANDOFF.md:114`, `BUILD_REPORT.md:234` — 15 (`apple_refresh_token`) do wgrania na prod, 14 (`claim_photo_slot`) „likely obsolete", oba nieaplikowane | App degraduje generycznie try/catch (`hydrateJobs` łyka błędy `AppState.swift:530-533`; `eventStatus` 404-fallback `BoothifyAPI.swift:324-329`). Nie crashuje, ale „brak crasha na brakujących tabelach" osiągnięty przez hurtowe łykanie błędów — łyka też realne bugi. Brak feature-detekcji migracji per se. |

## CUT — powierzchnia statyczna/AI (Część A.4)

Kod AI/on-device **naprawdę wycięty**. Grep `Photobooth-ai/*.swift`:

| Cel | Status | Dowód |
|---|---|---|
| StylePicker, PhotoStyle | **ABSENT** | 0 trafień |
| InstantLooks | **ABSENT** | 0 trafień |
| Green screen / Vision / `VNGenerateForegroundInstanceMask` | **ABSENT** | 0 trafień, brak `import Vision` |
| PhotoUploadQueue | **ABSENT** | 0 (tylko `Booth360UploadQueue`) |
| Gemini / AI image-gen | **PARTIAL (martwe refy)** | brak klienta; martwe komentarze `APIError.swift:27`, `BoothifyAPI.swift:97`; przykład w `BoothifyAPI.swift:10-12` cytuje funkcje `uploadPhoto/generatePhoto/pollUntilCompleted` które **nie istnieją** |
| ModeSelection | **ABSENT** | 0 trafień |
| PhotoboothLandingView | **PARTIAL (martwy ref)** | plik usunięty; martwy komentarz `AppState.swift:195` |
| stary AI ResultView | **PARTIAL (martwe refy)** | plik usunięty; martwe komentarze `SettingsMVPViews.swift:243,861` |
| print / AirPrint | **ABSENT** | 0 trafień |
| GIF / burst / boomerang / photo strip | **FOUND (relikt danych)** | `EventSettings.swift:88` `CaptureMode` wciąż ma `.photoStrip/.gif/.boomerang`; `CaptureSettings.alsoGenerateGif/reverseGif` `:122-123`; strip-layout `:424-425` |
| face-count / `VNDetectFaceRectangles` | **ABSENT** | 0 trafień |
| **Route enum** | **CLEAN** | `RootView.swift:6` (`home/events/settings`) + `settings*`/`booth360*`; brak tras foto-ery |

**Relikty foto-ery, które przeżyły cut (model danych + copy):** patrz Część B.1.

## DEVIATIONS (wszystkie udokumentowane w DECISIONS_LOG)

33 numerowane decyzje; każde odejście od blueprintu ma uzasadnienie. Kluczowe:
hub duality (`:30-33`), QRSheet moot → ShareSheet (`:35-37`), OnboardingQuiz cut
(`:41-42`), test-send removed (`:43-44`), master cap count-based (`:60-62`),
mock share links wyeliminowane (`:70-72`), E2E floor 20KB vs 8–15MB (`:76-78`),
per-frame CI zamiast CoreAnimationTool (`:93-95`), stabilization ladder honesty
(`:108-112`), `publicShareURL` at SIGN (`:118-121`). **Wszystkie uzasadnione.**
Niedokumentowany drift (kosmetyczny): brak `BOOTHIFY_360_BLUEPRINT.md` w repo;
`TriggerStateMachine` w `RecordingTrigger.swift` zamiast osobnego pliku.

## Wniosek Część A

Silnik renderu jest **realny, nie stub** (AVFoundation + AssetReader/Writer +
VideoToolbox H.264, realny per-frame overlay, realny chunked reverse, uczciwy
clamp slow-mo). Capture realny. Config, gating i artefakty faz sprawdzają się.
**Systemowe zastrzeżenie:** każde „GATE GREEN" to Gate A (symulator/syntetyk);
wszystko co wymaga sprzętu/venue odroczone do niezweryfikowanego HANDOFF.
„v1 COMPLETE" (`PROGRESS.md:280`) przecenia — to **„v1 code-complete,
device-unverified"**. Realne luki: (1) 240 fps niepodpięte; (2) nagłówki
`Booth360RecordingView.swift:7-9` / `Booth360.swift:79-80` kłamią o mock-capture;
(3) `booth360Jobs` bez persystencji → „survives reinstall" przeceniony;
(4) `progress` bez default → ryzyko cichej utraty historii; (5) stale komentarze
FFmpeg/AI.

---

# CZĘŚĆ B — AUDYT SETTINGS

## B.1 — Relikty statycznej budki

### Martwe modele danych (zdefiniowane, dekodowane, ZERO UI i ZERO konsumenta w renderze)

| Relikt | plik:linia | Klasyfikacja | Rekomendacja |
|---|---|---|---|
| `CaptureSettings` (cała struktura: mode, countdowny, numberOfPhotos, alsoGenerateGif, reverseGif, roamingPhotographerMode, outputSize…) | `EventSettings.swift:115-129`, pole `:11`, decode `:44` | **STATIC-BOOTH LEFTOVER** — żaden widok nie czyta `.capture` | Usunąć całą strukturę + pole. |
| `CaptureMode` (`singlePhoto/photoStrip/gif/boomerang/video`) | `EventSettings.swift:87-99` | **LEFTOVER** — photo-strip/GIF/boomerang to wycięta powierzchnia | Usunąć. |
| `OutputSize` (square/portrait/landscape) | `EventSettings.swift:101-113` | **LEFTOVER** — 360 quality idzie przez `AI360Settings.videoQuality` | Usunąć. |
| `PrintPaperSize` (4×6, 5×7…) | `EventSettings.swift:405-416` | **LEFTOVER** — 360 nie drukuje | Usunąć. |
| `PrintLayout` (strip 4-photo…) | `EventSettings.swift:418-429` | **LEFTOVER** — druk stripów | Usunąć. |
| `StickerPack` (emoji chips) | `EventSettings.swift:433-452` | **LEFTOVER** — komentarz `:524-527` sam mówi „Premium replacement for the old 'Stickers'"; enum dangling | Usunąć. |
| `GallerySlideshowSettings` + `SlideTransition` | `EventSettings.swift:382-401` | **UNCLEAR / prawdopodobnie leftover** — referencje tylko w EventSettings; nic nie czyta struktury | Zostawić TYLKO jeśli toolbar Album ją konsumuje (obecnie nie); inaczej usunąć. |

### `mirrorSelfie` — flagowane na życzenie
- Pole `EventSettings.swift:159`; UI `SettingsDetailViews.swift:41` + subtitle `SettingsHubView.swift:137`; konsument `CameraController.swift:22-26`.
- **UNCLEAR, skłania się ku LEFTOVER (rename).** Koncept „selfie" (flip przedniej kamery) to model statycznej budki — na obrotowej platformie 360 kamera orbituje gościa, nie robi selfie z ręki. Wciąż podpięte, więc nie martwe. **Rekomendacja: zachować możliwość mirror, przemianować na „Mirror front camera" (już wewnętrzna nazwa w `CameraController`), rozważyć default `preferredCamera = .back` dla ramienia rig.** Redundantne hardkodowane copy „Back · Mirrored selfie off" w `RootView.swift:394`.

### Duplikaty / wątpliwe dla 360
| Setting | plik:linia | Klasyfikacja | Rekomendacja |
|---|---|---|---|
| `roamingPhotographerMode` | `EventSettings.swift:160` + `SettingsDetailViews.swift:111`; DUPLIKAT `:124` (w CaptureSettings) | **LEFTOVER** — „roaming photographer" chodzi i fotografuje; sprzeczne z fixed spinning platform; wartość nikt nie czyta | Usunąć oba. |
| `pal25FpsRecording` | `EventSettings.swift:161` + `SettingsDetailViews.swift:113` | **UNCLEAR** — możliwe 360-relevant (EU broadcast), ale brak konsumenta w grep | Zostawić jeśli recorder czyta; inaczej martwy toggle. |
| `flash` (`FlashBehavior`) | `EventSettings.swift:162` + `SettingsDetailViews.swift:105` | **UNCLEAR** — flash still-photo; dla spinu istotny jest `ai360.blinkFlashWhileRecording` (`:236`); ten picker bez konsumenta | Prawdopodobnie leftover — skonsolidować z kontrolą flash 360 lub usunąć. |

### Stale copy (user-facing, odnosi się do wyciętej powierzchni)
- `PaywallView.swift:79` „Unlock **AI portraits**, 360, **printing** and white-label branding." — sprzedaje AI portraits i printing (oba wycięte). **Przepisać.**
- MARK-i sekcji: `EventSettings.swift:174` `// MARK: - AI Portraits`, `SettingsDetailViews.swift:125` `// MARK: - AI Portraits`, `SettingsMVPViews.swift:37` `// MARK: - Print Setup`. **Przemianować.**
- „AI results / AI-generated images / cinematic AI styles / AI photo booth platform": `SettingsMVPViews.swift:60,117,502`, `AboutBoothifyView` (`SettingsHubView.swift:339`). **Przepisać na język video/spin.**

## B.2 — Kompletność realnych ustawień 360

**Istnieją i podpięte do UI:** kamera (preferred, mirror, **stabilization preset z device-gating + crop preview** `SettingsDetailViews.swift:47-88`, zoom, rotation, flash, PAL25), **Motion** (`MotionTemplate` + `RampCurve` `:145-164`), soundtrack/bumpers, recording (countdown, duration 2–20s, save original, blink flash), quality (720p/1080p + bitrate 4–30 Mbps), auto-start na ruch, **timeline editor** (`CaptureTimelineEditor`), clip fallback (direction+speed), pre-record text, Brand Overlay, Sharing/limits/URL, Email/SMS+Twilio, Lock PIN.

**Braki / niespójności (z kodu):**
1. `clipDirection.backwards` redundantny — `effectiveSegments` (`EventSettings.swift:282-286`) traktuje `.reverse` i `.backwards` identycznie; picker pokazuje oba (`SettingsDetailViews.swift:264`). **Usunąć `.backwards` lub nadać odrębne zachowanie.**
2. `exportPreset` (`RenderSpec.Preset`) — pole modelu `EventSettings.swift:243-244` **BEZ UI**. Operator nie wybierze presetu eksportu. **Dodać picker.**
3. Legacy karta „Soundtrack & overlays" — cała `ComingSoonRow` (locked), duplikuje realną kartę „Soundtrack & bumpers"; 5 pól placeholder `EventSettings.swift:256-259`. **Usunąć placeholder card + pola.**
4. Disclaimer/Email wording stale-photo: `EventSettings.swift:472` „photo being processed by AI"; `EmailSMSSettings` `:358-360` „Your photo/AI photo". **Przepisać na video/spin.**
5. Brak jawnego ustawienia rotacji platformy / spin-speed poza `recordingDurationSeconds`. Jeśli obrót jest app-driven → **MISSING**; jeśli platforma kręci się niezależnie → OK. **Do weryfikacji (nie do rozstrzygnięcia z kodu settings).**
6. `cinematicExtended` V2-locked (`StabilizationPreset.swift:19`, filtrowany `SettingsDetailViews.swift:56`, „coming later" `:82`) — **celowe, nie luka.**

## B.3 — Mapa językowa

**Języki runtime: EN (default) + DE.** `Loc.swift:13-27`:
```swift
static func t(_ en: String, pl _: String, de: String) -> String {
    switch lang {
    case "de": return de
    default:   return en   // pl i reszta → English
    }
}
```
- **Polski WYŁĄCZONY.** Parametr `pl _:` (nienazwany/ignorowany), brak `case "pl"`. Decyzja produktowa `Loc.swift:9-12` (2026-07-07): „Polish market is NOT targeted … `pl:` stays so hundreds of call sites keep compiling; intentionally ignored."
- **35 linii z polskimi znakami — WSZYSTKIE wewnątrz argumentu `pl:` w `Loc.t(...)`** → klasyfikacja (a) intencjonalna lokalizacja, ale **MARTWA** (nigdy nie rozwiązywana). Pliki: `Booth360ResultView.swift` (67,69,185,186,198,275,304,340,623,661), `Booth360.swift` (41-46), `Booth360ProcessingView.swift` (23-27,105,115,142,155,156,268,280,286), `OverlaySpec.swift:89`, `Booth360RecordingView.swift` (73,191), `KioskAttractView.swift` (61,87,100,142).
- **Grep polskich znaków POZA linią `Loc.t`/`pl:` → ZERO trafień. Brak hardkodowanego polskiego wyciekającego w UI. Zero bugów typu (b).**
- Cały ekran ustawień to hardkodowany angielski BEZ `Loc.t` — **zgodne z decyzją** „operator/admin UI stays English" (`Loc.swift:6`). Brak mieszania języków.

**Rekomendacja:** albo (a) włączyć `case "pl": return pl` w `Loc.swift:21-26` jeśli Polska wraca na roadmapę, albo (b) usunąć parametr `pl:` i ~35 martwych tłumaczeń. Nie zostawiać half-wired.

---

# TL;DR

**Technicznie apka jest zdrowsza niż sugeruje jej własna dokumentacja komentarzy.**
Render, capture, backend-client, gating i fazy są realne i zweryfikowane vs kod.
Trzy klasy długu:

1. **Kłamiące komentarze/copy** — nagłówki „mock capture", refy „FFmpeg renderer",
   copy „AI portraits/printing/AI photo booth". Kod jest 360-video; opisy zostały w foto-erze.
2. **Relikty foto-ery w MODELU danych** — `CaptureSettings`/`CaptureMode`/`OutputSize`/
   `PrintPaperSize`/`PrintLayout`/`StickerPack` wciąż dekodowane w każdym evencie;
   `roamingPhotographerMode`, `mirrorSelfie` (rename), `/p/{photoId}` z żywym UI,
   `SurveyResponse.photoId`, osierocony `PostResultSurveySheet`.
3. **Przecenione twierdzenia** — „v1 COMPLETE" = code-complete/device-unverified;
   „clip history survives reinstall" = tylko dla uploaded + tylko po re-wejściu (brak
   lokalnej persystencji `booth360Jobs`); 240 fps zaimplementowane ale niepodpięte.

Braki funkcjonalne 360 do rozważenia: brak UI dla `exportPreset`, redundantny
`clipDirection.backwards`, martwa karta „Soundtrack & overlays" placeholder,
disclaimer/email wording stale-photo, ewentualny brak kontroli spin-speed.

Lokalizacja czysta: EN+DE żywe, polski celowo martwy (35 linii do usunięcia
lub re-enable jedną linią).
