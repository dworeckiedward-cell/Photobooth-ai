# Boothify 360 — playbook

> Wyprowadzony z metody FACET (4 dni, 13 commitów, code-complete), **skalibrowany
> pod to, co Boothify już ma** — a ma sporo. To nie jest lista rzeczy do dodania.
> To jest lista rzeczy, których brakuje, plus ostrzeżenia gdzie metoda FACET
> **nie przenosi się** i zaszkodzi.
>
> Data: 15 lipca 2026 · Stan Boothify: `ce37a70`, v1 code-complete, device-unverified

---

## 0. Reality check — zanim cokolwiek ruszysz

**Twoja ocena („zbudowane na szuja") jest nieprawdziwa.** Dowody z `APP_OVERVIEW.md`:

| Boothify ma | FACET ma |
|---|---|
| `gate.sh` = build + pełna suita, **jedyne kryterium merge'a**, 56 testów / 0 failures | **Zero testów.** Bramka = "Debug + Release zielone" |
| `LayoutSnapshotTests` — 8 ekranów do PNG | Screenshoty ręczne |
| Test dowodzący, że PIN nigdy nie jest enkodowany | — |
| `AUDIT_REPORT.md` — "co realne, co było overclaim" | `UX_AUDIT.md` (heurystyki, nie overclaim) |
| **Honesty rules** — zero obietnic funkcji, których nie ma | Reguła istnieje, nieudokumentowana |
| Honesty clamp w `RenderSpec` (nie obiecuje fps, którego nie było) | — |
| Persystencja jobów przez restart | `ResultCache` (offline snapshot) |
| `StorageLifecycle` przy niskim miejscu na dysku | — |
| Kolejka uploadów z backoffem, offline-safe | — |
| `CrashRestoreManager` | — |
| Sentry + `NetworkMonitor` | PostHog |
| Lokalizacja EN/DE | Tylko EN |
| `ASO_METADATA.md` — zwalidowane metadane EN+DE, keywords, plan A/B | — |
| Łagodna degradacja bez backendu | Częściowa (ResultCache) |

> **Wniosek: nie rób rewrite'u.** Ten kod ma dyscyplinę, której FACET nie ma.
> Ty patrzysz na niego oczami z dzisiaj i widzisz braki, ale nie widzisz,
> że tam jest suita testowa i log audytowy, których w FACET nie ma.

### Anty-wzorzec, który cię czeka
> Najłatwiejszy sposób na spalenie tygodnia: wejść w istniejący kod z nową wiedzą,
> uznać że „trzeba to zrobić porządnie" i zacząć przepisywać. **Refactor z rozpędu
> to nie jest postęp — to jest przesuwanie kodu.** Boothify jest code-complete.
> Odległość do sklepu to nie jakość kodu, tylko urządzenie + konto Apple.

---

## 1. 🚨 PILNE — sprawdź to dziś, 10 minut

### Guideline 3.1.2 — toggle free trial
Boothify ma `PaywallView` + `StoreManager` (StoreKit 2).

**Od połowy stycznia 2026 Apple masowo odrzuca paywalle z togglem free trial.**
- Guideline **3.1.2**: *"purchase screen includes a toggle to add or remove a free trial… confusing and may prevent users from understanding that they are committing to an auto-renewing subscription"*
- **Bez ogłoszenia, bez okresu przejściowego, odwołania nie działają**
- Apki wcześniej zatwierdzone **nie mogą wypchnąć update'u**, dopóki go nie usuną
- Superwall potwierdził bezpośrednio z Apple: toggle zakazany całkowicie

**Sprawdź:** czy `PaywallView` ma switch/toggle przełączający trial on/off.
Jeśli tak — **wywal przed submitem.**

### Reszta checklisty 3.1.2 (i tak trzeba przed submitem)
- [ ] Cena **i okres rozliczeniowy** widoczne prominentnie (≥16pt), nie drobnym drukiem obok dużej mylącej kwoty
- [ ] Pełna etykieta planu, okres nieskracany (*"Operator Annual — 1-year subscription, $X billed yearly"*)
- [ ] **Terms of Use i Privacy Policy — linki NA PAYWALLU**, nie tylko w Settings/na stronie
- [ ] **Restore Purchases** na paywallu
- [ ] Zero przesadzonych claimów; nie nazywaj „free" czegoś, co obciąża po trialu
- [ ] Jeśli trial: **wizualny timeline** (Day 1 dostęp → Day N przypomnienie → Day X obciążenie). To teraz wzorzec aprobowany przez Apple i najbezpieczniejsze zastąpienie toggle'a

---

## 2. ⛔ Czego NIE przenosić z FACET — to zaszkodzi

**FACET jest B2C. Boothify jest B2B. To są dwa różne biznesy.**

| Decyzja FACET | Dlaczego nie działa w Boothify |
|---|---|
| **Hard paywall, freemium odrzucone** | Argument brzmiał: *każdy skan = ~$0.15 vision API, więc free riderzy kosztują realną kasę*. **Boothify ma ZERO kosztu krańcowego per render** — to jest cały twój differentiator. **Argument nie obowiązuje. Freemium jest tu realną opcją.** |
| **7-dniowy trial** | Wynikał z **cooldownu re-scanu = 7 dni** w FACET. Boothify nie ma cooldownu. Twoja jednostka wartości to **event**, nie dzień. Trial powinien być prawdopodobnie mierzony **eventami lub renderami**, nie kalendarzem |
| **~21% churnu/mies, 10k pobrań/mies** | To jest matematyka weekly B2C. **Operator, który zarabia $500-1500 na evencie, nie churnuje jak chłopak z TikToka.** B2B w ścieżce przychodu = niski churn, wysoki LTV |
| **Influencerzy + rev-share + offer codes** | Operatorzy budek 360 nie kupują z TikToka. Kanały: **grupy FB dla operatorów eventowych, targi branżowe, poczta pantoflowa między operatorami, YouTube-tutoriale**. Zupełnie inna gra |
| **$7.99/tydz** | Konsumencki tier. **Twoja cena jest prawdopodobnie za niska.** Operator liczy koszt vs $500-1500/event — $49-99/mies to dla niego zaokrąglenie |
| **Superwall + RevenueCat** | Sensowne przy B2C A/B na tysiącach userów. Przy setkach operatorów **czysty StoreKit 2 (który masz) może wystarczyć** i oszczędza fee + integrację |
| **Score → reveal → paywall (peak impulse)** | Boothify nie ma momentu impulsu. **Ma moment dowodu: pierwszy udany event.** Paywall powinien siedzieć tam, nie po onboardingu |

### Czego FACET powinien nauczyć się OD Boothify
- **`gate.sh` jako jedyne kryterium merge'a** + realna suita testowa
- **Layout snapshot tests**
- **`AUDIT_REPORT.md`** — dokumentowanie, co było overclaim
- **Honesty rules** jako zapisana zasada, nie intuicja
- **Sentry** (FACET nie ma crash reportingu)

---

## 3. ✅ Co przenosi się wprost

### 3.1 Spec jako jedyne źródło prawdy
Boothify ma dokumenty rozsypane po 15 plikach. FACET ma **jeden** `APEX_FULL_DOCUMENTATION.md` (14 części), a `PROJECT_STATUS.md` to living status.

> **Nie przepisuj tego.** Ale ustal, **który plik jest kanoniczny** dla każdej klasy decyzji, i zapisz to w `README.md`. Dziś przy pytaniu „jaka jest cena?" nie wiadomo, czy patrzeć w `DECISIONS.md`, `ASO_METADATA.md`, czy w kod.

**Reguła FACET, która się sprawdza:** gdy zmieniasz decyzję, **przeszukaj CAŁY spec.**
Przy zmianie trialu 3→7 dni w FACET okazało się, że *"3-day"* siedziało w **~18 miejscach** — exec summary, pricing, GTM, checklist, draft Privacy/Terms, sekwencja mailowa, mockup HTML (włącznie z gałęzią JS, która **w ogóle nie miała linii o trialu**). Bez tego spec kłamie ci za tydzień.

### 3.2 Bramki milestone'ów
FACET: każdy milestone ma **bramkę** — konkretny, weryfikowalny dowód, że skończone.
Boothify już to ma w lepszej formie: **`gate.sh` = jedyne kryterium merge'a.**

> **Zachowaj to.** To jest lepsze niż FACET. Dodaj tylko: **Release musi się kompilować** — to jest dowód, że nic z `#if DEBUG` nie wyciekło do produkcji.

### 3.3 Checkpointy przy dużych zmianach
Przy restyle FACET (dotykał każdego ekranu) reguła brzmiała:

```
1. Merge + regeneracja projektu + weryfikacja green → commit
2. Ekstrakcja tokenów → build green → commit → STOP, pokaż tabelę, CZEKAJ
3. Zastosuj na 2 ekrany → screenshot → commit
4. Zastosuj na resztę → screenshot → commit
5. Pass accessibility → fix → commit
```

> **STOP przed aplikacją jest kluczowy.** To jedyne miejsce, gdzie jeden błąd
> mnoży się przez wszystkie ekrany. Zatrzymanie kosztuje jedną wiadomość,
> oszczędza całą rundę.

### 3.4 Fidelity check zamiast „zrobione"
Zawsze każ porównać wynik ze wzorcem i **wypisać, gdzie odbiegł i dlaczego.**
FACET dostał uczciwą listę: kryształ ~80%, week strip nie zbudowany (nowe UX),
FAB pominięty (zmienia hit-testing). **Pięć oflagowanych kompromisów bije pięć cichych.**

### 3.5 Audyt UX z PRAWDZIWEGO urządzenia
Najlepsze znaleziska FACET wyszły dopiero, gdy appka poszła na fizyczny telefon:
- Niespójny auto-advance (czuć tylko kciukiem, nie widać w kodzie)
- Gęste listy bez ikon

> **Boothify tego jeszcze nie przeszedł.** `NEEDS_DEVICE.md` istnieje, ale
> Gate B nie zaliczony. **To jest twoja największa niewiadoma** — i przy appce,
> której rdzeń to kamera + termika + render, dużo większa niż w FACET.

### 3.6 Compliance jako guardrail, nie fix
W FACET toggle'a **nie było** w specu — ale M5 mówił *"build via Superwall"*,
a **stockowe szablony Superwalla toggle zawierają.** Guardrail zapisany mimo
że problemu nie było.

> **Analogia dla Boothify:** twój `PaywallView` jest ręczny (StoreKit 2), więc
> ryzyko szablonu nie istnieje. Ale zapisz zakaz w decyzjach, żeby ktoś (albo ty
> za pół roku) nie dodał toggle'a „bo Adam Lyttle pokazał, że podwaja przychód".

### 3.7 Deep research PRZED decyzją
FACET: trzy raporty (natywne iOS, walidacja rynku, paywall/trial) **przed** budowaniem.
Każdy zawierał **kontr-sygnał** — miejsce, gdzie rekomendacja jest najprawdopodobniej błędna.

> Dla Boothify brakuje odpowiednika **walidacji rynku**: ilu jest operatorów budek 360,
> ile płacą za software dziś, kto jest konkurencją (Salsa/Booth apps?), jaka jest
> struktura cenowa branży. **Bez tego cena $X to zgadywanie.**

### 3.8 Kontr-sygnały zapisane w specu
FACET zapisał: *"Umax/LooksMax/RateByFresh nie mają trialu w ogóle — kategoria
może konwertować na czystej ciekawości. To najprawdopodobniejsze miejsce,
gdzie się mylimy. A/B test #1."*

> Zapisz swoje. Np.: *"Zakładamy, że on-device render bez chmury to differentiator.
> Kontr-sygnał: jeśli operatorzy mają wifi na 90% eventów, to nie jest przewaga,
> tylko ograniczenie (brak funkcji chmurowych)."*

### 3.9 Progi porażki ustalone Z GÓRY
FACET ma pre-committed failure criteria (trial→paid <20-25%, install→trial <5%,
retencja D30 <23%). Bez nich będziesz racjonalizował złe liczby.

> Boothify potrzebuje swoich. Np.: trial→paid operatorów, % operatorów robiących
> ≥2 eventy w miesiącu, retencja M3, % renderów kończących się deliverem.

---

## 4. Stack — co warto, czego nie

### Rzeczy z FACET, które realnie warto rozważyć

| | Werdykt | Dlaczego |
|---|---|---|
| **Tuist** | ⚠️ **Rozważ, nie rób od razu** | FACET: nigdy nie edytuj `.pbxproj` ręcznie — to eliminuje całą klasę merge-konfliktów i stale-project bugów. **Ale migracja istniejącego projektu to realna robota.** Jeśli `.xcodeproj` cię nie boli — zostaw. Jeśli boli (konflikty, znikające pliki) — migruj |
| **`#if DEBUG` na całe dev scaffolding** | ✅ **Tak** | Boothify ma już `BOOTHIFY_REQUIRE_AUTH` i mock kamery. Upewnij się, że **wszystko** dev-only jest za `#if DEBUG` i że **Release się kompiluje** — to jest dowód |
| **Deterministyczne trasy debug** | ✅ **Tak, wysoka wartość** | FACET dodał `-onboardingRoute reveal` + `-demoData YES` — jedna komenda, powtarzalny ekran, bez backendu i bez prawdziwego selfie. **Dla Boothify ekwiwalent: `-renderDemo` z syntetycznym klipem** (masz już `TestVideoFactory`!). Zwraca się przy trzeciej iteracji |
| **Superwall** | ❌ **Nie** | Przy B2B/setkach operatorów remote A/B nie ma sygnału statystycznego. StoreKit 2 wystarczy |
| **RevenueCat** | ⚠️ **Może** | Przydaje się do stanu subskrypcji (kto lapsował → win-back). Ale przy StoreKit 2 + małej skali to nadmiar |
| **PostHog** | ⚠️ | Masz Sentry (crash). Brakuje **analityki produktowej** — ile renderów per event, gdzie odpada operator. Bez tego lecisz na ślepo. Ale to nie musi być PostHog |
| **Rive** | ❌ | FACET potrzebował do kryształu. Boothify nie ma odpowiednika |

### Rzeczy, których Boothify NIE potrzebuje z FACET
- Vision API / Anthropic — **twój differentiator to brak AI i brak kosztu per render.** Nie psuj tego
- Supabase auth/RLS — masz Sign in with Apple + własny backend
- App Group / widżety — brak sensownego use-case (operator patrzy na appkę na evencie, nie na Home Screen)
- Push retention engine — B2B nie potrzebuje streaków

---

## 5. UI/UX — co przenieść

### Zasady FACET, które sprawdziły się w praktyce

**1. Hierarchia = częstotliwość dotyku, nie waga emocjonalna.**
> W FACET: score oglądasz raz przy reveału, protokół odhaczasz 2× dziennie.
> Mockupy dawały pół ekranu score'owi. **Były projektowane pod screenshota,
> nie pod kciuk o 8 rano.**
>
> **Dla Boothify:** co operator dotyka najczęściej na evencie? To ma dostać ekran.
> Prawdopodobnie: START, status renderu, delivery. Nie: ustawienia, kalendarz.

**2. Jeden glow focus na ekran.** Jedna dominanta. Boothify już to ma zapisane w `DESIGN_SYSTEM.md` — trzymaj się.

**3. Mockuj 3 ekrany, nie 25.** Reszta wyprowadza się z tokenów. FACET zamockował Home + Reveal + jeden quiz screen; Claude Code wyprowadził pozostałe ~22 ekrany z DesignSystem.
> **Dla Boothify:** Landing/Attract + Recording/Processing + Result. To definiuje język.

**4. Mockup ≠ produkt. Zawsze weryfikuj kontrast.**
> W restyle FACET **trzy** wartości z mockupu nie przeszły AA:
> eyebrow `#A5A9BB` = **2,6:1** (katastrofa), amber jako tekst = **1,9:1**, danger = **3,5:1**.
> Wszystkie trzeba było przyciemnić — czyli **odejść od mockupu.** To jest właściwa decyzja.
>
> **Boothify jest dark-only z fioletem** — kontrast już przechodzi. **Ale jeśli
> kiedykolwiek pójdziesz w jasny motyw: cały dowód AA jest nieważny, przelicz od zera.**

**5. Redundancja jest kosztem.** W FACET kafelki „Target 88" i „Oil control 66" **dublowały tekst hero 40px wyżej**. Wywalone → odzyskane ~15% ekranu, zero utraty informacji.
> Szukaj tego u siebie: co jest napisane dwa razy?

**6. Affordance, która prowadzi donikąd, to bug.** Mockup FACET miał chevrony `>` na wierszach protokołu, sugerujące detal view, którego nie ma. **Wycięte.**

**7. Struktura > estetyka.** Przy restyle FACET dwie rzeczy zostały odrzucone mimo że były w mockupie: **5. zakładka („Insights")** = zmiana produktu, nie restyle. **Center FAB** = zmienia hit-testing nawigacji.
> Reguła: *jeśli zmienia strukturę — pomiń i oflaguj.*

**8. Inwersja motywu to nie podmiana tokenów.** Frosted glass i glow zaprojektowane pod ciemne **nie działają** na jasnym (`.ultraThinMaterial` pod forced-light **mrozi biel**). Każdy komponent do audytu, nie do recoloru.
> Dotyczy cię tylko jeśli ruszysz motyw. **Nie ruszaj** — twój dark/fiolet jest spójny.

---

## 6. Prompt library — gotowce do Claude Code

### 6.1 Otwarcie sesji (zawsze)
```
New session. Get your bearings: read README.md and HANDOFF.md, run
git log --oneline, run git branch -a, check git status. Then [zadanie].

Follow the repo's conventions. gate.sh is the merge criterion — it must pass.
Release must compile clean; that's the proof no DEBUG scaffolding leaked.
```

### 6.2 Audyt 3.1.2 (zrób DZIŚ)
```
Audit PaywallView + StoreManager against App Store Guideline 3.1.2 as
enforced in 2026. Do NOT change code yet — report first.

Check for:
1. A free-trial TOGGLE (a switch that adds/removes a trial, typically
   defaulting to off, flipping between plans). Apple began mass-rejecting
   this in mid-January 2026 under 3.1.2 — no announcement, no grace period,
   appeals don't work, and previously-approved apps can't ship updates until
   it's removed. If present, this is a launch blocker.
2. Price AND billing period prominence (≥16pt, not fine print next to a
   larger misleading figure)
3. Plan labels with unabbreviated billing period
4. Terms of Use + Privacy Policy links IN THE PAYWALL UI (not only Settings,
   not only the website)
5. Restore Purchases affordance on the paywall
6. Any claim that could read as exaggerated or as calling it "free" when it
   charges after a trial

Report what's compliant, what isn't, and what you'd change. Rank by
rejection risk.
```

### 6.3 Audyt UX (po device pass, nie przed)
```
Run a UX audit. Do NOT write code — produce a report.

I've now used the app on a real device at [kontekst], and I'm bringing real
friction I felt: [twoje obserwacje].

Treat those as symptoms of a broader class of problem. Then audit the full
[flow] for: friction & drop-off risk per screen, interaction consistency,
affordances, copy clarity, and pacing.

For each finding give: (a) screen/flow, (b) the problem and which heuristic
it violates, (c) severity (high/medium/low), (d) a concrete fix. Rank by
impact. Be critical and opinionated — I want real problems, not reassurance.
If a screen should be cut entirely, say so.

Write the report to UX_AUDIT_[X].md and give me the top findings ranked.
```

### 6.4 Duża zmiana — z checkpointami
```
[Zadanie]

EXECUTION ORDER — commit at each checkpoint. Do not do this in one shot.
1. [Przygotowanie] → gate.sh green → commit
2. [Rdzeń — np. tokeny/kontrakt] → green → commit → STOP AND SHOW ME
   BEFORE APPLYING IT ANYWHERE. Wait for my go-ahead.
3. [Zastosuj na 2 ekrany] → screenshot → commit
4. [Zastosuj na resztę] → screenshot → commit
5. [Weryfikacja] → fix → commit

FIDELITY CHECK — before you report, compare your output against the target
side by side. Tell me honestly where it diverges and why: what you couldn't
reproduce, what you deliberately changed, what it'd take to close the gap.
Don't tell me it matches if it doesn't — I'm going to look myself.

IF YOU GET STUCK, STOP AND ASK. Don't force something that doesn't work and
don't silently invent a substitute. Ship best-effort, flag it, give me options.
I'd rather have 5 flagged compromises than 5 silent ones.

HARD CONSTRAINTS: [co się nie zmienia]

WHAT "DONE" MEANS: gate.sh green is the floor, not the goal.
```

### 6.5 Zmiana decyzji w dokumentacji
```
[Decyzja] is now [X], not [Y]. Record the reasoning so it isn't re-litigated.

Then sweep the ENTIRE repo for contradictions — every doc, every markdown
file, every string in code, every mockup. When we changed this on another
project it turned out the old value was in ~18 places, including a JS ternary
in an HTML prototype where one branch had no trial line at all. Find all of
them and reconcile. Tell me what you found inconsistent.
```

### 6.6 Ultracode (duże migracje)
```
/effort ultracode
```
> `xhigh` + automatyczna orkiestracja workflow. Modele: **Fable 5, Opus 4.8, Opus 4.7.**
> Sesyjne, resetuje się przy restarcie. ~500k tokenów na dużą migrację.
> **Warto:** audyty, migracje, research sweepy. **Nie warto:** literówka, jedna poprawka.
> Budżet: `ultracode +500k` — sufit twardy, agenci rzucają błędem po przekroczeniu.

---

## 7. Kolejność — co realnie robić

### Dziś (bez urządzenia, bez konta Apple)
1. **Audyt 3.1.2 paywalla** (prompt 6.2) — 10 minut, może uratować odrzucenie
2. **Ustal kanoniczne źródło prawdy** — który plik rządzi którą klasą decyzji, zapisz w README
3. **Dodaj `-renderDemo`** — deterministyczna trasa do renderu z `TestVideoFactory`, bez kamery. Będzie ci potrzebna przy każdej iteracji

### Gdy paszport → konto Apple aktywne (24-48h)
> **Uwaga: ten sam paszport odblokowuje FACET i Boothify.** Obie appki są
> code-complete i obie stoją na tym samym dokumencie:
> - AASA z prawdziwym Team ID (deep linki) — **Apple**
> - App Store Connect: produkty subskrypcji, App Privacy label, age rating — **Apple**
> - TestFlight — **Apple**

4. **Gate B — device pass.** To jest twoja największa niewiadoma:
   - Kamera na prawdziwym sprzęcie (symulator ma mock!)
   - **Termika przy realnym renderze** — `ThermalMonitor` istnieje, ale nietestowany pod obciążeniem
   - Realny czas renderu vs `PerfBudget`
   - Reverse encoder na długim klipie (pamięć)
   - Tryb kiosku + Guided Access
   - Delivery: QR, SMS przez Twilio, AirDrop
   - Zachowanie offline → odzyskanie sieci → kolejka dogania
5. Migracja Supabase 15 (+ decyzja o 14)
6. AASA deployment
7. Screenshoty (w tym iPad), App Privacy, age rating, disclosure Sentry
8. Natywne tłumaczenie DE (metadane gotowe w `ASO_METADATA.md`)
9. **Submit**

### Po launchu
10. **Walidacja rynku** — ilu jest operatorów, ile płacą dziś, kto konkuruje
11. **Przemyślenie ceny** — prawdopodobnie za nisko dla B2B
12. Analityka produktowa (ile renderów/event, gdzie odpada operator)
13. Kanały: grupy FB operatorów, targi, poczta pantoflowa

---

## 8. Otwarte pytania — do rozstrzygnięcia, nie do zgadnięcia

1. **Cena.** Operator zarabia $500-1500/event. Ile płaci dziś za software? Jaka jest struktura branży? **Bez researchu to zgadywanie.**
2. **Trial mierzony czym?** Dniami (kalendarz) czy **eventami/renderami** (jednostka wartości)? B2B: operator może kupić w styczniu i mieć pierwszy event w marcu — 7-dniowy trial jest wtedy bezużyteczny.
3. **Gdzie siedzi paywall?** FACET: po reveału (peak impulse). Boothify **nie ma momentu impulsu — ma moment dowodu: pierwszy udany event.** Paywall po pierwszym renderze? Po pierwszym evencie? Przed?
4. **Freemium?** Zero kosztu krańcowego per render = argument, który zabił freemium w FACET, **tu nie obowiązuje.** Np. X renderów/mies za darmo, potem subskrypcja?
5. **Czy on-device to naprawdę differentiator?** Kontr-sygnał: jeśli operatorzy mają wifi na 90% eventów, to jest ograniczenie, nie przewaga.
6. **Tuist?** Tylko jeśli `.xcodeproj` realnie boli.

---

## 9. Zasady, które przetrwały FACET

> **1. „Prosta łapka ≠ pół gwizdka."** Umax i Cal AI wystartowały bez widżetów,
> Dynamic Island i rings. Wypuść v1, dodawaj w update'ach.
>
> **2. Najpierw dowód, potem skala.** Cal AI: $2 000 na test w social media,
> Reddit i Discord → 100k pobrań → **dopiero potem** 150 influencerów i $7k/dzień.
> Nikt nie „zaplanował miliona userów".
>
> **3. Ordering, nie duration.** Milestone zajmuje ci 30 minut — problemem nie jest
> koszt, tylko kolejność. Blockery przed bajerami.
>
> **4. Release zielony to podłoga, nie cel.** Dowodzi, że nic nie zepsute.
> Nie dowodzi, że wygląda.
>
> **5. Pięć oflagowanych kompromisów bije pięć cichych.**
>
> **6. Mockup ≠ produkt.** Narzędzia projektowe nie znają twoich ograniczeń.
> Pierwszych pięć mockupów FACET miało kobiecy avatar, zieleń i kreskówkowego
> potwora — bo ChatGPT nie wiedział, co budujesz.
>
> **7. Kod nie jest wąskim gardłem. Ty jesteś — i papiery.**
> Dwie appki code-complete stoją na jednym dokumencie w domu rodzinnym.

---

*Playbook wygenerowany 15 lipca 2026 na podstawie sesji FACET (13 commitów, 4 dni)
i `APP_OVERVIEW.md` Boothify (`ce37a70`). Wszystkie liczby App Store dotyczą
egzekwowania z początku-połowy 2026 — **zweryfikuj przed submitem.***
