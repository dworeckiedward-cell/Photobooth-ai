import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Photos

struct ResultView: View {
    @Environment(AppState.self) private var app
    // QW3 — respect iOS Accessibility → Motion → Reduce Motion. When ON,
    // skip the 0.7s reveal animation; the photo just appears.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let eventId: UUID
    let photoId: UUID

    /// Latest known state of the photo. Populated by polling.
    @State private var photo: Photo?
    @State private var pollAttempts = 0
    @State private var pollTask: Task<Void, Never>?
    @State private var retryCount = 0
    @State private var loadedImage: UIImage?
    @State private var messageIndex: Int = 0
    @State private var particlePhase: Bool = false
    @State private var haloPulse: Bool = false
    @State private var dotPhase: Bool = false
    @State private var revealOpacity: Double = 0
    @State private var glow: Double = 0
    @State private var showConfetti: Bool = false
    @State private var sharePresented: Bool = false
    @State private var qrPresented: Bool = false
    @State private var emailPresented: Bool = false
    @State private var smsPresented: Bool = false
    @State private var surveyPresented: Bool = false
    @State private var surveyDone: Bool = false
    @State private var saveToPhotosErrorMessage: String? = nil
    @State private var saveToPhotosErrorPresented: Bool = false
    @State private var whatsAppUnavailablePresented: Bool = false

    private var publicURL: URL {
        BoothifyAPI.shared.publicResultURL(photoId: photoId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let photo {
                switch photo.status {
                case .pending, .uploaded, .generating:
                    generatingState
                case .completed:
                    completedView(photo: photo)
                case .failed:
                    failedView(photo: photo)
                }
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .navigationTitle(photo?.style.label ?? "Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: "\(photoId)-\(retryCount)") {
            await startPolling()
        }
        .onAppear { NotificationManager.shared.cancelPhotoReadyNotifications() }
        .onDisappear { pollTask?.cancel() }
        .sheet(isPresented: $qrPresented) {
            QRSheet(url: publicURL.absoluteString)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $sharePresented) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $emailPresented) {
            EmailSheet(photoId: photoId)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $smsPresented) {
            SMSSheet(photoId: photoId, eventId: eventId)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $surveyPresented) {
            PostResultSurveySheet(
                settings: app.settings(for: eventId).survey,
                onSubmit: { response in
                    var stamped = response
                    stamped.photoId = photoId
                    app.appendSurveyResponse(stamped, for: eventId)
                    surveyDone = true
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Cannot Save Photo", isPresented: $saveToPhotosErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveToPhotosErrorMessage ?? "An unknown error occurred.")
        }
        .alert("WhatsApp Not Installed", isPresented: $whatsAppUnavailablePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("WhatsApp is not installed on this device. Share the photo link via SMS, Email, or QR Code instead.")
        }
        // Single merged onChange for .completed — handles both survey trigger and auto-print.
        .onChange(of: photo?.status) { _, newStatus in
            guard newStatus == .completed else { return }

            // Auto-print when enabled in settings.
            if app.settings(for: eventId).print.enabled,
               app.settings(for: eventId).print.autoPrintAfterCapture {
                Task { await printPhoto() }
            }

            // Post-result survey — delayed slightly so the reveal animation lands first.
            guard !surveyDone else { return }
            let s = app.settings(for: eventId).survey
            if s.enabled {
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    surveyPresented = true
                }
            }
        }
    }

    // MARK: - States

    // Fixed particle data — built once at type load, never re-shuffled on render.
    private static let particles: [GeneratingParticle] = {
        let seeds: [(dx: CGFloat, dy: CGFloat, sz: CGFloat, op: Double, dur: Double, del: Double, accent: Bool)] = [
            (-95,  -80, 5, 0.7, 3.2, 0.0, true),
            ( 80,  -60, 4, 0.5, 2.8, 0.4, false),
            (-40,  110, 6, 0.6, 3.6, 0.9, true),
            ( 110, -30, 4, 0.4, 2.6, 1.5, false),
            (-70,   50, 5, 0.7, 3.0, 0.2, true),
            (  20, -115, 4, 0.5, 3.8, 1.1, false),
            ( 115,  70, 6, 0.6, 2.9, 0.7, true),
            (-115,  10, 4, 0.4, 3.4, 1.8, false),
            (  55,  95, 5, 0.7, 2.7, 0.3, true),
            (  -5, -105, 4, 0.5, 3.1, 1.3, false),
            ( -90,  -50, 6, 0.6, 3.5, 0.6, true),
            (  60,  -90, 4, 0.4, 2.5, 1.9, false),
        ]
        return seeds.map {
            GeneratingParticle(
                offset: CGSize(width: $0.dx, height: $0.dy),
                size: $0.sz,
                opacity: $0.op,
                duration: $0.dur,
                delay: $0.del,
                isAccent: $0.accent
            )
        }
    }()

    private var generatingState: some View {
        ZStack {
            // 1. Particle field
            ZStack {
                ForEach(Array(Self.particles.enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(p.isAccent
                              ? BoothifyTheme.violet.opacity(0.5)
                              : BoothifyTheme.violet.opacity(0.25))
                        .frame(width: p.size, height: p.size)
                        .offset(
                            x: p.offset.width,
                            y: particlePhase ? p.offset.height - 40 : p.offset.height + 10
                        )
                        .opacity(particlePhase ? p.opacity : 0)
                        .animation(
                            reduceMotion ? nil :
                                .linear(duration: p.duration)
                                .repeatForever(autoreverses: false)
                                .delay(p.delay),
                            value: particlePhase
                        )
                }
            }

            // 2. Content column
            VStack(spacing: BoothifySpacing.lg) {

                // Icon + halo
                ZStack {
                    // 3. Pulsing violet halo (behind icon)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [BoothifyTheme.violet.opacity(0.18), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(haloPulse ? 1.15 : 0.85)
                        .animation(
                            reduceMotion ? nil :
                                .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                            value: haloPulse
                        )

                    // Central icon block
                    RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
                        .fill(BoothifyTheme.surface1)
                        .frame(width: 96, height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
                                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                        )
                    Image(systemName: "wand.and.stars")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.violet)
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                        .accessibilityHidden(true)
                }

                // 4. Copy block
                VStack(spacing: BoothifySpacing.xs) {
                    Text("Crafting your portrait")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(funnyMessage(index: messageIndex))
                        .font(.subheadline)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                        .id(messageIndex)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: messageIndex)
                }

                // 5. Three-dot pulse indicator
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(BoothifyTheme.violet)
                            .frame(width: 8, height: 8)
                            .scaleEffect(dotPhase ? 1.0 : 0.6)
                            .animation(
                                reduceMotion ? nil :
                                    .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(i) * 0.2),
                                value: dotPhase
                            )
                    }
                }

                // 6. Footer
                Text("Usually ready in ~15 seconds")
                    .font(.caption)
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
        }
        .padding(BoothifySpacing.xl)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                particlePhase = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                haloPulse = true
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                dotPhase = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating your photo")
    }

    @ViewBuilder
    private func completedView(photo: Photo) -> some View {
        ZStack(alignment: .bottom) {
            photoCard(photo: photo).ignoresSafeArea(edges: .bottom)
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            actionsBar(photo: photo)
        }
    }

    @ViewBuilder
    private func failedView(photo: Photo) -> some View {
        VStack(spacing: BoothifySpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                    .fill(BoothifyTheme.error.opacity(0.12))
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                            .stroke(BoothifyTheme.error.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.error)
                    .accessibilityHidden(true)
            }

            VStack(spacing: BoothifySpacing.xs) {
                Text("Generation failed")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(photo.errorMessage ?? "Something went wrong. Try a different style or retake.")
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BoothifySpacing.xl)
            }

            if photo.errorMessage?.contains("Timed out") == true {
                Button {
                    Haptics.tap(.medium)
                    retryPolling()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 260)
                .padding(.top, BoothifySpacing.sm)
            }

            Button {
                Haptics.tap()
                app.pop()
            } label: {
                Label("Try another style", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 260)
            .padding(.top, photo.errorMessage?.contains("Timed out") == true ? 0 : BoothifySpacing.sm)
        }
        .padding(.horizontal, BoothifySpacing.lg)
    }

    private func retryPolling() {
        photo = nil
        pollAttempts = 0
        messageIndex = 0
        retryCount += 1
    }

    // MARK: - Subviews

    private func photoCard(photo: Photo) -> some View {
        ZStack {
            if let url = photo.generatedURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.4))) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let img):
                        img.resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                            .onAppear {
                                if loadedImage == nil { renderToUIImage(url: url) }
                            }
                    case .failure:
                        Rectangle().fill(photo.style.accentGradient)
                    @unknown default:
                        Rectangle().fill(photo.style.accentGradient)
                    }
                }
            } else {
                Rectangle().fill(photo.style.accentGradient)
            }

            // Brand overlay (client logo / event watermark) on top of the AI result.
            let brand = app.settings(for: eventId).brandOverlay
            if brand.rendersOnResults {
                BrandOverlayLayer(settings: brand, eventId: eventId)
            }
        }
        .shadow(color: Color.black.opacity(glow * 0.6), radius: 40)
        .opacity(revealOpacity)
        .scaleEffect(revealOpacity < 1 ? 0.94 : 1.0)
        .onAppear { playRevealAnimation() }
    }

    private func actionsBar(photo: Photo) -> some View {
        VStack(spacing: BoothifySpacing.sm) {
            metadataStrip(photo: photo)

            // Primary CTA — guest delivery. SMS is the fastest path to the guest's
            // own device; it should be the prominent, full-width action.
            Button {
                Haptics.tap()
                smsPresented = true
            } label: {
                HStack(spacing: BoothifySpacing.sm) {
                    Image(systemName: "message.fill").font(.body.weight(.semibold))
                    Text("Send to Guest (SMS)")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Send the photo link to the guest's phone via SMS")

            // Secondary share actions
            HStack(spacing: BoothifySpacing.xs) {
                ShareActionButton(symbol: "qrcode", label: "QR Code") {
                    Haptics.tap()
                    qrPresented = true
                }
                ShareActionButton(symbol: "envelope.fill", label: "Email") {
                    Haptics.tap()
                    emailPresented = true
                }
                ShareActionButton(symbol: "phone.bubble.fill", label: "WhatsApp") {
                    Haptics.tap()
                    let text = "Your photo is ready: \(publicURL.absoluteString)"
                    let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    guard let whatsAppURL = URL(string: "https://wa.me/?text=\(encoded)") else { return }
                    if UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!) {
                        UIApplication.shared.open(whatsAppURL)
                    } else {
                        whatsAppUnavailablePresented = true
                    }
                }
                ShareActionButton(symbol: "printer.fill", label: "Print") {
                    Haptics.tap()
                    Task { await printPhoto() }
                }
                .opacity(app.settings(for: eventId).print.enabled ? 1 : 0.3)
                // Operator save — secondary, not the primary guest action
                ShareActionButton(symbol: "square.and.arrow.down", label: "Save") {
                    saveToPhotos()
                }
                .opacity(loadedImage == nil ? 0.4 : 1)
                .accessibilityHint("Saves the generated image to your Photos library")
                // IM1: native system share sheet (AirDrop, Messages, etc.)
                ShareLink(item: publicURL,
                          subject: Text("Your photo from Boothify"),
                          message: Text("Tap to open →")) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up").font(.title3)
                        Text("Share").font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(BoothifyTheme.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                            .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                .accessibilityLabel("Open native share sheet — AirDrop, Messages, Mail")
            }

            // Tertiary navigation row
            HStack(spacing: BoothifySpacing.xs) {
                Button {
                    Haptics.tap()
                    app.pop()
                } label: {
                    Label("Another style", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    Haptics.tap()
                    app.popUntil { route in
                        if case .camera = route { return true }
                        return false
                    }
                } label: {
                    Label("Retake", systemImage: "camera.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    Haptics.tap()
                    app.popUntil { route in
                        if case .eventHub = route { return true }
                        return false
                    }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(BoothifySpacing.md)
        .background(BoothifyTheme.bg.opacity(0.92))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(BoothifyTheme.surfaceLine).frame(height: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        .padding(.horizontal, BoothifySpacing.sm)
        .padding(.bottom, BoothifySpacing.sm)
    }

    // MARK: - Metadata strip (background removal, stickers, etc.)

    @ViewBuilder
    private func metadataStrip(photo: Photo) -> some View {
        let bg = app.settings(for: eventId).backgroundRemoval
        let chips = activeChips(photo: photo, bg: bg)
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        HStack(spacing: 5) {
                            Image(systemName: chip.symbol).font(.caption2.weight(.bold))
                            Text(chip.label).font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(chip.tint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(chip.tint.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(chip.tint.opacity(0.45), lineWidth: 0.5))
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func activeChips(
        photo: Photo,
        bg: BackgroundRemovalSettings
    ) -> [MetadataChip] {
        var out: [MetadataChip] = []
        out.append(MetadataChip(id: "style", symbol: "wand.and.stars", label: photo.style.label, tint: BoothifyTheme.violet))
        if bg.enabled {
            let label: String = switch bg.mode {
            case .off: "Background: off"
            case .remove: "Background removed"
            case .replaceColor: "BG color \(bg.backgroundHex)"
            case .replaceImage: "BG: \(bg.backgroundImageName ?? "image")"
            }
            out.append(MetadataChip(id: "bg", symbol: "person.crop.rectangle.badge.xmark", label: label, tint: BoothifyTheme.violet))
        }
        let brand = app.settings(for: eventId).brandOverlay
        if brand.rendersOnResults {
            out.append(MetadataChip(id: "brand", symbol: "rosette", label: "Brand overlay", tint: BoothifyTheme.amber))
        }
        return out
    }

    private struct MetadataChip: Identifiable {
        let id: String
        let symbol: String
        let label: String
        let tint: Color
    }

    // MARK: - Polling

    private func startPolling() async {
        pollTask?.cancel()
        pollAttempts = 0

        // Funny message rotation while waiting.
        let messageTask = Task { @MainActor in
            while !Task.isCancelled, photo == nil || (photo?.status.isTerminal == false) {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeInOut(duration: 0.4)) { messageIndex += 1 }
            }
        }
        defer { messageTask.cancel() }

        // Polling loop — short interval (1s), terminal status ends.
        for _ in 0..<60 {
            if Task.isCancelled { return }
            do {
                let next = try await BoothifyAPI.shared.getPhoto(id: photoId)
                photo = next
                if next.status == .completed {
                    Haptics.notify(.success)
                    if UIApplication.shared.applicationState != .active {
                        NotificationManager.shared.notifyPhotoReady(
                            eventName: "Event",
                            styleName: next.style.label
                        )
                    }
                    return
                } else if next.status == .failed {
                    Haptics.notify(.error)
                    return
                }
            } catch {
                // Transient — swallow and retry. After enough failures, give up.
                pollAttempts += 1
                if pollAttempts > 5 {
                    photo = Photo(
                        id: photoId,
                        style: photo?.style ?? .astronauta,
                        status: .failed,
                        generatedUrl: nil,
                        errorMessage: (error as? APIError)?.errorDescription ?? error.localizedDescription,
                        generationTimeMs: nil,
                        createdAt: nil,
                    )
                    return
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
        // Timed out
        if photo?.status.isTerminal != true {
            photo = Photo(
                id: photoId,
                style: photo?.style ?? .astronauta,
                status: .failed,
                generatedUrl: photo?.generatedUrl,
                errorMessage: "Timed out waiting for generation. Try again.",
                generationTimeMs: nil,
                createdAt: nil,
            )
        }
    }

    // MARK: - Helpers

    private func renderToUIImage(url: URL) {
        Task.detached(priority: .userInitiated) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run { loadedImage = image }
        }
    }

    private func playRevealAnimation() {
        guard revealOpacity == 0 else { return }
        // QW3 — Reduce Motion honors the user's accessibility setting.
        // Snap to final values without easing/glow/confetti when ON.
        if reduceMotion {
            revealOpacity = 1
            glow = 0
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.05)) { revealOpacity = 1 }
        withAnimation(.easeOut(duration: 0.75)) { glow = 0.55 }
        withAnimation(.easeIn(duration: 0.75).delay(0.75)) { glow = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Haptics.notify(.success)
        }
        showConfetti = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showConfetti = false
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = [publicURL]
        if let img = loadedImage { items.insert(img, at: 0) }
        return items
    }

    @MainActor
    private func printPhoto() async {
        guard let url = photo?.generatedURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }

        let settings = app.settings(for: eventId).print
        let eventName = app.event(id: eventId)?.name
        let qrURL: URL? = settings.includeQRCode
            ? BoothifyAPI.shared.publicResultURL(photoId: photoId)
            : nil

        PrintEngine.print(image: image, settings: settings, eventName: eventName, qrURL: qrURL)
    }

    private func saveToPhotos() {
        guard let raw = loadedImage else { Haptics.notify(.error); return }
        let brand = app.settings(for: eventId).brandOverlay
        // M7: bake the brand overlay into the exported image so it survives
        // the share. SwiftUI overlay is preview-only — without bake the saved
        // file is the raw AI image.
        let img = brand.rendersOnResults
            ? bakeBrandOverlay(into: raw, settings: brand, eventId: eventId)
            : raw

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: img)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                Haptics.notify(.success)
                            } else {
                                Haptics.notify(.error)
                                saveToPhotosErrorMessage = error?.localizedDescription ?? "Failed to save the photo."
                                saveToPhotosErrorPresented = true
                            }
                        }
                    }
                case .denied, .restricted:
                    Haptics.notify(.error)
                    saveToPhotosErrorMessage = "Photo library access was denied. Go to Settings > Privacy > Photos and allow access for Boothify."
                    saveToPhotosErrorPresented = true
                case .notDetermined:
                    // requestAuthorization always resolves to a concrete status — this
                    // case is unreachable after the callback fires, but handle it defensively.
                    Haptics.notify(.error)
                    saveToPhotosErrorMessage = "Photo library permission not determined. Please try again."
                    saveToPhotosErrorPresented = true
                @unknown default:
                    Haptics.notify(.error)
                    saveToPhotosErrorMessage = "An unexpected error occurred while accessing the photo library."
                    saveToPhotosErrorPresented = true
                }
            }
        }
    }

    /// Composite the brand overlay onto `base` and return a new UIImage. Mirrors
    /// the SwiftUI `BrandOverlayLayer` positioning so on-screen preview and
    /// saved file match.
    private func bakeBrandOverlay(
        into base: UIImage,
        settings: BrandOverlaySettings,
        eventId: UUID
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: base.size))

            let shorter = min(base.size.width, base.size.height)
            let side = shorter * CGFloat(settings.size)
            let pad = shorter * CGFloat(settings.padding)

            switch settings.logoSource {
            case .boothifySample, .uploaded:
                let logo: UIImage?
                if settings.logoSource == .uploaded,
                   let relative = settings.customLogoRelativePath {
                    logo = BrandOverlayLayer.loadUploadedLogo(eventId: eventId, relative: relative)
                        ?? UIImage(named: settings.logoAssetName)
                } else {
                    logo = UIImage(named: settings.logoAssetName)
                }
                guard let logo else { return }
                let rect = anchoredRect(side: side, pad: pad, container: base.size, position: settings.position)
                ctx.cgContext.setAlpha(CGFloat(settings.opacity))
                logo.draw(in: rect)
            case .textFallback:
                let fontSize = max(11, side * 0.30)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(CGFloat(settings.opacity)),
                ]
                let text = settings.overlayText as NSString
                let textSize = text.size(withAttributes: attrs)
                let rect = anchoredRect(side: max(side, textSize.width + 16),
                                        pad: pad,
                                        container: base.size,
                                        position: settings.position)
                // Pill background for legibility.
                let bg = UIColor.black.withAlphaComponent(0.42 * CGFloat(settings.opacity))
                bg.setFill()
                let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
                bgPath.fill()
                text.draw(
                    in: CGRect(
                        x: rect.midX - textSize.width / 2,
                        y: rect.midY - textSize.height / 2,
                        width: textSize.width,
                        height: textSize.height
                    ),
                    withAttributes: attrs
                )
            }
        }
    }

    /// Convert anchor + size + padding into a concrete drawing rect.
    private func anchoredRect(
        side: CGFloat,
        pad: CGFloat,
        container: CGSize,
        position: BrandOverlayPosition
    ) -> CGRect {
        switch position {
        case .topLeft:
            return CGRect(x: pad, y: pad, width: side, height: side)
        case .topRight:
            return CGRect(x: container.width - side - pad, y: pad, width: side, height: side)
        case .bottomLeft:
            return CGRect(x: pad, y: container.height - side - pad, width: side, height: side)
        case .bottomRight:
            return CGRect(x: container.width - side - pad,
                          y: container.height - side - pad,
                          width: side, height: side)
        case .center:
            return CGRect(x: (container.width - side) / 2,
                          y: (container.height - side) / 2,
                          width: side, height: side)
        }
    }

    /// Rotating status copy displayed below the headline while we poll
    /// for the generated photo. Kept brief + professional — operator may
    /// be holding the iPad in front of a paying client.
    private func funnyMessage(index: Int) -> String {
        let messages = [
            "Reading the scene…",
            "Composing your portrait…",
            "Applying the style…",
            "Refining the details…",
            "Almost there…",
        ]
        return messages[index % messages.count]
    }
}

// MARK: - Confetti

private struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let angle: Double
        let speed: Double
        let rotationSpeed: Double
        let delay: Double
    }

    private let pieces: [Piece]
    @State private var animating = false

    private static let palette: [Color] = [
        Color(red: 0.545, green: 0.361, blue: 0.965), // violet
        .white,
        Color(red: 0.063, green: 0.725, blue: 0.506), // emerald
        Color(red: 0.960, green: 0.620, blue: 0.043), // amber
        Color(red: 0.851, green: 0.275, blue: 0.937), // fuchsia
    ]

    init() {
        var built: [Piece] = []
        built.reserveCapacity(24)
        for i in 0..<24 {
            let color: Color = Self.palette[i % Self.palette.count]
            let angle: Double = Double(i) / 24.0 * .pi * 2
            let speed: Double = 200.0 + Double(i % 6) * 22.0
            let rotationSpeed: Double = 180.0 + Double(i % 5) * 36.0
            let delay: Double = Double(i % 4) * 0.04
            built.append(Piece(color: color, angle: angle, speed: speed, rotationSpeed: rotationSpeed, delay: delay))
        }
        pieces = built
    }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height * 0.45
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: 6, height: 12)
                        .rotationEffect(.degrees(animating ? p.rotationSpeed : 0))
                        .offset(
                            x: animating ? cos(p.angle) * p.speed : 0,
                            y: animating ? sin(p.angle) * p.speed - 60 : 0
                        )
                        .opacity(animating ? 0 : 1)
                        .position(x: cx, y: cy)
                        .animation(.easeOut(duration: 1.1).delay(p.delay), value: animating)
                }
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Generating particle model

private struct GeneratingParticle {
    let offset: CGSize
    let size: CGFloat
    let opacity: Double
    let duration: Double
    let delay: Double
    let isAccent: Bool
}

// MARK: - Share buttons & sheets

private struct ShareActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 8)
            .background(BoothifyTheme.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share via \(label)")
    }
}

private struct EmailSheet: View {
    let photoId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            VStack(spacing: BoothifySpacing.md) {
                Text(sent ? "Email sent" : "Send to email")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, BoothifySpacing.lg)

                if sent {
                    Spacer()
                    VStack(spacing: BoothifySpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(BoothifyTheme.emerald)
                        Text("Check your inbox")
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                    }
                    Spacer()
                } else {
                    TextField("you@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(.horizontal, BoothifySpacing.md)
                        .frame(minHeight: 52)
                        .background(BoothifyTheme.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                        .padding(.horizontal, BoothifySpacing.lg)
                        .foregroundStyle(.white)

                    if let errorMessage {
                        HStack(spacing: BoothifySpacing.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(errorMessage)
                                .font(.footnote)
                        }
                        .foregroundStyle(BoothifyTheme.error)
                        .padding(.horizontal, BoothifySpacing.lg)
                    }

                    Button {
                        send()
                    } label: {
                        Text(sending ? "Sending…" : "Send")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sending || !email.contains("@"))
                    .padding(.horizontal, BoothifySpacing.lg)

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func send() {
        sending = true
        errorMessage = nil
        Task {
            do {
                try await BoothifyAPI.shared.sendEmail(photoId: photoId, email: email)
                Haptics.notify(.success)
                sent = true
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                Haptics.notify(.error)
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            sending = false
        }
    }
}

private struct SMSSheet: View {
    let photoId: UUID
    let eventId: UUID
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var phone: String = ""
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            VStack(spacing: BoothifySpacing.md) {
                Text(sent ? "SMS sent" : "Send via SMS")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, BoothifySpacing.lg)

                if sent {
                    Spacer()
                    VStack(spacing: BoothifySpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(BoothifyTheme.emerald)
                        Text("Message on its way")
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                    }
                    Spacer()
                } else {
                    TextField("+48 500 111 222", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(.horizontal, BoothifySpacing.md)
                        .frame(minHeight: 52)
                        .background(BoothifyTheme.surface1)
                        .overlay(
                            RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                        .padding(.horizontal, BoothifySpacing.lg)
                        .foregroundStyle(.white)

                    if let errorMessage {
                        HStack(spacing: BoothifySpacing.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(errorMessage)
                                .font(.footnote)
                        }
                        .foregroundStyle(BoothifyTheme.error)
                        .padding(.horizontal, BoothifySpacing.lg)
                    }

                    Button {
                        send()
                    } label: {
                        Text(sending ? "Sending…" : "Send")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sending || phone.filter(\.isNumber).count < 7)
                    .padding(.horizontal, BoothifySpacing.lg)

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func send() {
        sending = true
        errorMessage = nil
        Task {
            do {
                // M5: prefer the operator's own Twilio (per-user direct REST).
                // Falls back to the global backend Twilio only when operator
                // hasn't connected their own account yet.
                if let creds = TwilioClient.shared.currentCredentials(), creds.isConfigured {
                    let emailSMS = app.settings(for: eventId).emailSMS
                    let event = app.event(id: eventId)
                    let link = BoothifyAPI.shared.publicResultURL(photoId: photoId).absoluteString
                    let body = renderTemplate(
                        template: emailSMS.smsBodyTemplate,
                        link: link,
                        eventName: event?.name ?? ""
                    )
                    let override = emailSMS.smsFromOverride.trimmingCharacters(in: .whitespaces)
                    _ = try await TwilioClient.shared.sendSMS(
                        to: phone.trimmingCharacters(in: .whitespaces),
                        body: body,
                        using: creds,
                        fromOverride: override.isEmpty ? nil : override
                    )
                } else {
                    try await BoothifyAPI.shared.sendSMS(photoId: photoId, phone: phone)
                }
                Haptics.notify(.success)
                sent = true
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                Haptics.notify(.error)
                if let twilioErr = error as? TwilioError {
                    errorMessage = twilioErr.errorDescription
                } else {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
            sending = false
        }
    }

    /// Replaces {{link}}, {{eventName}} tokens used in the SMS template.
    /// Mirrors the same substitution the backend does for its template, so
    /// switching paths doesn't change what the guest sees.
    private func renderTemplate(template: String, link: String, eventName: String) -> String {
        template
            .replacingOccurrences(of: "{{link}}", with: link)
            .replacingOccurrences(of: "{{eventName}}", with: eventName)
    }
}

// MARK: - QR sheet

struct QRSheet: View {
    let url: String

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            VStack(spacing: BoothifySpacing.md) {
                Text("Scan with your phone")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, BoothifySpacing.lg)

                Text("Opens your photo on the device's browser")
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textSecondary)

                qrCode
                    .frame(width: 240, height: 240)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                    .padding(.top, BoothifySpacing.xs)
                    .accessibilityLabel("QR code for \(url)")

                Text(url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(BoothifyTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BoothifySpacing.lg)
                    .textSelection(.enabled)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let img = qrUIImage(from: url) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
        } else {
            Color.black
        }
    }

    private func qrUIImage(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaled = output.transformed(by: transform)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Share sheet bridge

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
