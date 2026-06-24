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
        }
        .navigationTitle("Instant looks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await buildThumbnails() }
        .alert("Saved", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
            Button("OK") { saveMessage = nil }
        } message: { Text(saveMessage ?? "") }
    }

    // MARK: - Picker

    private var pickerPhase: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                Text("Pick a look")
                    .font(BoothifyType.displayMedium)
                    .foregroundStyle(.white)
                    .padding(.top, BoothifySpacing.sm)
                Text("Instant, on-device — no waiting.")
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)

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
                .padding(.bottom, BoothifySpacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
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
                    Label("Save photo", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                HStack(spacing: BoothifySpacing.sm) {
                    if let url = shareURL {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Button { printPhoto(image) } label: {
                        Label("Print", systemImage: "printer")
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
                        Label("Another look", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        Haptics.tap()
                        app.popToRoot()
                    } label: {
                        Label("Done", systemImage: "checkmark")
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
        let data = capturedImageData
        Task.detached(priority: .userInitiated) {
            let out = LocalLookProcessor.process(data, look: look)
            // Write a temp file so ShareLink shares the real JPEG (Messages/Mail/
            // WhatsApp/AirDrop), not a re-encoded screenshot.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("boothify-\(UUID().uuidString).jpg")
            try? out.write(to: url)
            await MainActor.run {
                processedData = out
                shareURL = url
            }
        }
    }

    private func savePhoto(_ image: UIImage) {
        Haptics.tap(.medium)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    saveMessage = "Allow photo access in Settings to save."
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, _ in
                    DispatchQueue.main.async {
                        Haptics.notify(success ? .success : .error)
                        saveMessage = success ? "Saved to your photos." : "Couldn't save the photo."
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
