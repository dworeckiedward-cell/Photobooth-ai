import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

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
    @State private var loadedImage: UIImage?
    @State private var messageIndex: Int = 0
    @State private var revealOpacity: Double = 0
    @State private var glow: Double = 0
    @State private var sharePresented: Bool = false
    @State private var qrPresented: Bool = false
    @State private var emailPresented: Bool = false
    @State private var smsPresented: Bool = false
    @State private var surveyPresented: Bool = false
    @State private var surveyDone: Bool = false

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
        .task(id: photoId) {
            await startPolling()
        }
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
        .onChange(of: photo?.status) { _, newStatus in
            // Trigger the post-result survey once we land on `.completed`.
            guard newStatus == .completed, !surveyDone else { return }
            let s = app.settings(for: eventId).survey
            if s.enabled {
                // Brief delay so the reveal animation gets a beat first.
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    surveyPresented = true
                }
            }
        }
    }

    // MARK: - States

    private var generatingState: some View {
        VStack(spacing: BoothifySpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                    .fill(BoothifyTheme.surface1)
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                            .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                    )
                Image(systemName: "sparkles")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
            }

            VStack(spacing: BoothifySpacing.xs) {
                Text("Generating photo")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(funnyMessage(index: messageIndex))
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .id(messageIndex)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: messageIndex)
            }

            ProgressView()
                .progressViewStyle(.linear)
                .tint(BoothifyTheme.violet)
                .frame(maxWidth: 200)

            Text("Average time: ~10 seconds")
                .font(.caption2)
                .foregroundStyle(BoothifyTheme.textMuted)
        }
        .padding(BoothifySpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating your photo")
    }

    @ViewBuilder
    private func completedView(photo: Photo) -> some View {
        ZStack(alignment: .bottom) {
            photoCard(photo: photo).ignoresSafeArea(edges: .bottom)
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

            Button {
                Haptics.tap()
                app.pop()
            } label: {
                Label("Try another style", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 260)
            .padding(.top, BoothifySpacing.sm)
        }
        .padding(.horizontal, BoothifySpacing.lg)
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
        .scaleEffect(0.98 + 0.02 * revealOpacity)
        .onAppear { playRevealAnimation() }
    }

    private func actionsBar(photo: Photo) -> some View {
        VStack(spacing: BoothifySpacing.sm) {
            metadataStrip(photo: photo)

            // Primary CTA
            Button {
                saveToPhotos()
            } label: {
                HStack(spacing: BoothifySpacing.sm) {
                    Image(systemName: "square.and.arrow.down").font(.body.weight(.semibold))
                    Text("Save to Photos")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(loadedImage == nil)
            .accessibilityHint("Saves the generated image to your Photos library")

            // Secondary share actions
            HStack(spacing: BoothifySpacing.xs) {
                ShareActionButton(symbol: "message.fill", label: "SMS") {
                    Haptics.tap()
                    smsPresented = true
                }
                ShareActionButton(symbol: "phone.bubble.fill", label: "WhatsApp") {
                    Haptics.tap()
                    let text = "Your photo is ready: \(publicURL.absoluteString)"
                    if let url = URL(string: "https://wa.me/?text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        UIApplication.shared.open(url)
                    }
                }
                ShareActionButton(symbol: "envelope.fill", label: "Email") {
                    Haptics.tap()
                    emailPresented = true
                }
                ShareActionButton(symbol: "qrcode", label: "QR Code") {
                    Haptics.tap()
                    qrPresented = true
                }
                // IM1: native AirDrop / system share
                ShareLink(item: publicURL,
                          subject: Text("Your photo from Boothify"),
                          message: Text("Tap to open →")) {
                    VStack(spacing: 4) {
                        Image(systemName: "airplayaudio").font(.title3)
                        Text("AirDrop").font(.caption2.weight(.medium))
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
        // Snap to final values without easing/glow when ON.
        if reduceMotion {
            revealOpacity = 1
            glow = 0
            return
        }
        withAnimation(.easeOut(duration: 0.7)) { revealOpacity = 1 }
        withAnimation(.easeOut(duration: 0.75)) { glow = 0.55 }
        withAnimation(.easeIn(duration: 0.75).delay(0.75)) { glow = 0 }
    }

    private var shareItems: [Any] {
        var items: [Any] = [publicURL]
        if let img = loadedImage { items.insert(img, at: 0) }
        return items
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
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        Haptics.notify(.success)
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
