import SwiftUI
import Photos

/// No-API photo path: pick an on-device "look" (Core Image), then save / print /
/// share the result immediately. Works with zero cloud AI — the booth stays fully
/// functional even when the Gemini backend is unavailable.
struct InstantLooksView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID
    let capturedImageData: Data

    @State private var thumbnails: [LocalLook: UIImage] = [:]
    @State private var selected: LocalLook? = nil
    @State private var processedData: Data? = nil
    @State private var shareURL: URL? = nil
    @State private var saveMessage: String? = nil
    @State private var reelGenerating = false
    @State private var reelURL: URL? = nil
    @State private var showReelShare = false
    /// Non-nil while a strip/look/backdrop render is in flight — drives the busy
    /// overlay so the guest gets immediate feedback (Vision backdrops take a beat).
    @State private var workingLabel: String? = nil

    private var eventName: String? {
        app.events.first(where: { $0.id == eventId })?.name
    }

    private let columns = [
        GridItem(.flexible(), spacing: BoothifySpacing.sm),
        GridItem(.flexible(), spacing: BoothifySpacing.sm),
        GridItem(.flexible(), spacing: BoothifySpacing.sm),
    ]

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            if let processed = processedData, let img = UIImage(data: processed) {
                resultPhase(image: img)
            } else {
                pickerPhase
            }

            if let label = workingLabel {
                busyOverlay(label)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: workingLabel)
        .navigationTitle("Instant looks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await buildThumbnails() }
        .alert("Saved", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
            Button("OK") { saveMessage = nil }
        } message: { Text(saveMessage ?? "") }
        .sheet(isPresented: $showReelShare) {
            if let url = reelURL {
                ActivityShareSheet(items: [url])
            }
        }
    }

    // MARK: - Picker

    private var pickerPhase: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                Text(Loc.t("Pick a look", pl: "Wybierz styl", de: "Wähle einen Look"))
                    .font(BoothifyType.displayMedium)
                    .foregroundStyle(.white)
                    .padding(.top, BoothifySpacing.sm)
                Text(Loc.t("Instant, on-device — no waiting.", pl: "Natychmiast, na urządzeniu — bez czekania.", de: "Sofort, auf dem Gerät — ohne Warten."))
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)

                sectionHeader(Loc.t("Create", pl: "Stwórz", de: "Erstellen"))

                // Differentiator: a classic photo strip from ONE photo in 4 looks.
                Button {
                    Haptics.tap(.medium)
                    makeStrip()
                } label: {
                    HStack(spacing: BoothifySpacing.sm) {
                        Image(systemName: "rectangle.split.1x2")
                            .font(.body.weight(.semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Loc.t("Classic photo strip", pl: "Klasyczny pasek zdjęć", de: "Klassischer Fotostreifen"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(Loc.t("Your photo in 4 looks — printable", pl: "Twoje zdjęcie w 4 stylach — do druku", de: "Dein Foto in 4 Looks — druckbar"))
                                .font(.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BoothifyTheme.textMuted)
                    }
                    .foregroundStyle(BoothifyTheme.violet)
                    .padding(BoothifySpacing.md)
                    .background(BoothifyTheme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                            .stroke(BoothifyTheme.violet.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)

                // Differentiator: a short looping video reel from ONE photo.
                Button {
                    Haptics.tap(.medium)
                    makeReel()
                } label: {
                    HStack(spacing: BoothifySpacing.sm) {
                        Image(systemName: "film")
                            .font(.body.weight(.semibold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Loc.t("Look reel · video", pl: "Wideo z lookami", de: "Look-Reel · Video"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(Loc.t("Your photo cycling through 6 looks", pl: "Twoje zdjęcie w 6 stylach", de: "Dein Foto in 6 Looks"))
                                .font(.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                        if reelGenerating {
                            ProgressView().tint(BoothifyTheme.violet)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.textMuted)
                        }
                    }
                    .foregroundStyle(BoothifyTheme.violet)
                    .padding(BoothifySpacing.md)
                    .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                            .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(reelGenerating)
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)

                sectionHeader(Loc.t("Looks", pl: "Style", de: "Looks"))

                LazyVGrid(columns: columns, spacing: BoothifySpacing.sm) {
                    ForEach(LocalLook.allCases) { look in
                        Button {
                            Haptics.tap(.medium)
                            apply(look)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if let thumb = thumbnails[look] {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        BoothifyTheme.surface2
                                        Image(systemName: look.symbol)
                                            .foregroundStyle(BoothifyTheme.textMuted)
                                    }
                                }
                                .frame(height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                                Text(look.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)

                // On-demand studio backdrops — segment the guest and drop them on
                // a premium backdrop instantly, no physical green screen needed.
                sectionHeader(Loc.t("Studio backdrops", pl: "Tła studyjne", de: "Studio-Hintergründe"))

                VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
                    LazyVGrid(columns: columns, spacing: BoothifySpacing.sm) {
                        ForEach(StudioBackdrop.allCases) { backdrop in
                            Button {
                                Haptics.tap(.medium)
                                applyBackdrop(backdrop)
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(backdrop.swatch)
                                        .frame(height: 80)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                        )
                                    Text(backdrop.label)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.bottom, BoothifySpacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Busy overlay

    /// Full-screen scrim + spinner shown while an on-device render is in flight,
    /// so a tap never looks like it did nothing (Visibility of System Status).
    private func busyOverlay(_ label: String) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: BoothifySpacing.md) {
                ProgressView().tint(.white).controlSize(.large)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(BoothifySpacing.xl)
            .background(BoothifyTheme.surface2, in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
        }
        .transition(.opacity)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Result

    private func resultPhase(image: UIImage) -> some View {
        VStack(spacing: BoothifySpacing.md) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.top, BoothifySpacing.sm)

            Spacer(minLength: 0)

            VStack(spacing: BoothifySpacing.sm) {
                Button { savePhoto(image) } label: {
                    Label(Loc.t("Save photo", pl: "Zapisz zdjęcie", de: "Foto speichern"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                HStack(spacing: BoothifySpacing.sm) {
                    if let url = shareURL {
                        ShareLink(item: url) {
                            Label(Loc.t("Share", pl: "Udostępnij", de: "Teilen"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Button { printPhoto(image) } label: {
                        Label(Loc.t("Print", pl: "Drukuj", de: "Drucken"), systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                HStack(spacing: BoothifySpacing.sm) {
                    Button {
                        Haptics.tap()
                        processedData = nil
                        shareURL = nil
                        selected = nil
                    } label: {
                        Label(Loc.t("Another look", pl: "Inny styl", de: "Anderer Look"), systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        Haptics.tap()
                        app.popToRoot()
                    } label: {
                        Label(Loc.t("Done", pl: "Gotowe", de: "Fertig"), systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.bottom, BoothifySpacing.lg)
        }
    }

    // MARK: - Actions

    private func apply(_ look: LocalLook) {
        selected = look
        workingLabel = Loc.t("Applying look…", pl: "Nakładam styl…", de: "Look wird angewendet…")
        let data = capturedImageData
        let overlay = app.settings(for: eventId).brandOverlay
        let eid = eventId
        Task.detached(priority: .userInitiated) {
            var out = LocalLookProcessor.process(data, look: look)
            // Bake the operator's brand overlay (logo / mark) for white-label,
            // print-ready output — same treatment as the AI result screen.
            if overlay.enabled, overlay.applyToResults, let img = UIImage(data: out) {
                out = BrandOverlayRenderer.bake(into: img, settings: overlay, eventId: eid)
                    .jpegData(compressionQuality: 0.92) ?? out
            }
            // Write a temp file so ShareLink shares the real JPEG (Messages/Mail/
            // WhatsApp/AirDrop), not a re-encoded screenshot.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("boothify-\(UUID().uuidString).jpg")
            try? out.write(to: url)
            await MainActor.run {
                processedData = out
                shareURL = url
                workingLabel = nil
            }
        }
    }

    // Left-aligned section header that lines up with the 620-wide content.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.top, BoothifySpacing.xs)
    }

    private func applyBackdrop(_ backdrop: StudioBackdrop) {
        workingLabel = Loc.t("Placing backdrop…", pl: "Wstawiam tło…", de: "Hintergrund wird gesetzt…")
        let data = capturedImageData
        let overlay = app.settings(for: eventId).brandOverlay
        let eid = eventId
        let bgSettings = BackgroundRemovalSettings(
            enabled: true,
            mode: .replaceImage,
            backgroundHex: "#0A0A0B",
            backgroundImageName: backdrop.storageName,
            applyToAIPortraits: false
        )
        Task.detached(priority: .userInitiated) {
            var out = BackgroundReplacer.process(data, settings: bgSettings)
            if overlay.enabled, overlay.applyToResults, let img = UIImage(data: out) {
                out = BrandOverlayRenderer.bake(into: img, settings: overlay, eventId: eid)
                    .jpegData(compressionQuality: 0.92) ?? out
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("boothify-\(UUID().uuidString).jpg")
            try? out.write(to: url)
            await MainActor.run {
                processedData = out
                shareURL = url
                workingLabel = nil
            }
        }
    }

    private func makeReel() {
        guard !reelGenerating else { return }
        reelGenerating = true
        LookReelComposer.compose(from: capturedImageData) { url in
            reelGenerating = false
            guard let url else {
                saveMessage = Loc.t("Couldn't make the reel.", pl: "Nie udało się utworzyć wideo.", de: "Reel konnte nicht erstellt werden.")
                return
            }
            reelURL = url
            showReelShare = true
        }
    }

    private func makeStrip() {
        workingLabel = Loc.t("Building strip…", pl: "Tworzę pasek…", de: "Streifen wird erstellt…")
        let data = capturedImageData
        let title = eventName
        let accent = UIColor(BoothifyTheme.violet)
        Task.detached(priority: .userInitiated) {
            let strip = PhotoStripComposer.compose(from: data, title: title, accent: accent)
            guard let strip else {
                await MainActor.run {
                    workingLabel = nil
                    saveMessage = Loc.t("Couldn't make the strip.", pl: "Nie udało się utworzyć paska.", de: "Streifen konnte nicht erstellt werden.")
                }
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("boothify-strip-\(UUID().uuidString).jpg")
            try? strip.write(to: url)
            await MainActor.run {
                processedData = strip
                shareURL = url
                workingLabel = nil
            }
        }
    }

    private func savePhoto(_ image: UIImage) {
        Haptics.tap(.medium)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    saveMessage = Loc.t("Allow photo access in Settings to save.", pl: "Zezwól na dostęp do zdjęć w Ustawieniach, aby zapisać.", de: "Erlaube den Fotozugriff in den Einstellungen zum Speichern.")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, _ in
                    DispatchQueue.main.async {
                        Haptics.notify(success ? .success : .error)
                        saveMessage = success
                            ? Loc.t("Saved to your photos.", pl: "Zapisano w zdjęciach.", de: "In deinen Fotos gespeichert.")
                            : Loc.t("Couldn't save the photo.", pl: "Nie udało się zapisać zdjęcia.", de: "Foto konnte nicht gespeichert werden.")
                    }
                }
            }
        }
    }

    private func printPhoto(_ image: UIImage) {
        Haptics.tap(.medium)
        PrintEngine.print(image: image, settings: app.settings(for: eventId).print, eventName: eventName)
    }

    // MARK: - Thumbnails

    private func buildThumbnails() async {
        let data = capturedImageData
        for look in LocalLook.allCases {
            if Task.isCancelled { return }
            let thumb = await Task.detached(priority: .utility) {
                LocalLookProcessor.thumbnail(data, look: look)
            }.value
            if let thumb { thumbnails[look] = thumb }
        }
    }
}
