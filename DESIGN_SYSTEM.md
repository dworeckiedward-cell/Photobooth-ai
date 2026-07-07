# Boothify 360 — Design System: ATMOSPHERIC GLASS (v2)

Źródło prawdy nowego języka wizualnego. Fundament: `Photobooth-ai/AtmosphericGlass.swift`
+ tokeny w `Theme.swift` / `Typography.swift`. Ekrany NIE ręcznie-robią szkła,
teł ani glow — używają poniższych. Commit fundamentu: `36cc758`, kaskada: `c4ce8ff`.

## Filary (każdy ekran)
1. Pełnoekranowe ciemne tło (`AtmosphericBackground`) pod całym UI.
2. Treść na mrożonym szkle (`.glassSurface(radius:)`).
3. Jedna dominująca linia typograficzna (`BoothifyType.hero`).
4. Mała pływająca pill-nawigacja (ikony; `BoothifyTabBar` w RootView).
5. Oddech — tło widoczne między elementami; max-width treści zostaje.
6. Jeden amber glow na ekran (`.glowAccent(intensity:)`) na kluczowej akcji.

## Komponenty

### `AtmosphericBackground(assetName: String? = nil)`
Deep violet/indigo gradient-mesh (3 chłodne pole + szept amberu) + scrim
góra/dół gwarantujący czytelność białego tekstu. `assetName` = hook pod
przyszły branding operatora (asset z bundla; systemu uploadu celowo brak).
`allowsHitTesting(false)`, `accessibilityHidden(true)`.
Użycie: pierwszy element ZStacka ekranu, zamiast `BoothifyTheme.bg.ignoresSafeArea()`.

### `.glassSurface(radius: CGFloat = BoothifyRadius.surface)`
`ultraThinMaterial` wymuszony dark + rim 1 px (biały 14→5% top-weighted) +
continuous radius + miękki cień. **Reduce Transparency → SOLID
`BoothifyTheme.bgElevated`** (obowiązkowy fallback dostępności).
Kaskaduje automatycznie przez: `AppCard`, legacy `Surface`
(`.boothifySurface`), `SettingsCard` — nie stosuj podwójnie.

### `.glowAccent(color: = amber, intensity: Double = 0.5)`
Miękka radialna poświata + shadow za elementem. 0.35 = szept, 0.7 = hero.
Zasada rzadkości: JEDNA na ekran (attract CTA, przycisk nagrywania, kod QR).
Statyczna (pulsowanie tylko tam, gdzie już było, za guardem reduce-motion).

## Tokeny dodane
| Token | Wartość | Rola |
|---|---|---|
| `BoothifyTheme.bgDeep` | 0.031/0.020/0.059 | niemal-czarna scena (era czarna) |
| `BoothifyTheme.bgElevated` | 0.08/0.07/0.12 | solidny fallback szkła |
| `BoothifyTheme.indigoGlow` | 0.24/0.20/0.55 | nikły pool przy górnej krawędzi |
| `BoothifyTheme.recording` | 0.94/0.20/0.20 | czerwień REC (z biegu v1) |
| `BoothifyType.hero` | largeTitle **heavy** | jedna dominująca linia ekranu |

## Paleta — role (ERA CZARNA, decyzja operatora 2026-07-07)
- **Tło = czerń.** `bgDeep` niemal czysta czerń; atmosfera to JEDEN nikły
  fioletowy pool u góry. Kalendarz i ustawienia czytają się jako czarne ekrany.
- **Fiolet (violet-500) = JEDYNY akcent interakcji** (CTA, glow, ikony,
  badge, liczniki). CTA: `AccentCTAButtonStyle` — biały tekst na fioletowym
  gradiencie.
- **Amber = WYCOFANY z UI.** Token istnieje wyłącznie dla semantyki
  `warning`; nie używać jako akcentu.
- **Home = wyjątek tła**: pełnoekranowy ambientowy klip budki
  (`BoothAmbient.mp4` przez `AmbientVideoView`) pod scrimem czytelności;
  Reduce Motion / brak asseta -> czarna atmosfera.
- Biel/biel-z-opacity = tekst wg hierarchii; tokeny textSecondary/Tertiary/Muted.
- `fuchsia`/`pink` = legacy, nieużywane w nowym UI (komentarz w Theme).

## Dostępność
- Reduce Transparency: szkło → solid (w `GlassSurface`, centralnie).
- Reduce Motion: pulsy/bounce za istniejącymi guardami; glow statyczny.
- Pill-nav: ikony 44 pt+ tap target; tytuły tabów jako `accessibilityLabel`.

## Jak dodać nowy ekran
```swift
ZStack {
    AtmosphericBackground()
    ScrollView {
        VStack(spacing: BoothifySpacing.lg) {
            Text(title).font(BoothifyType.hero)          // 1 dominanta
            content.padding(BoothifySpacing.md)
                   .glassSurface()                        // treść na szkle
            PrimaryCTA().glowAccent(intensity: 0.6)       // 1 glow
        }
        .frame(maxWidth: 620).frame(maxWidth: .infinity)  // oddech
    }
}
```
