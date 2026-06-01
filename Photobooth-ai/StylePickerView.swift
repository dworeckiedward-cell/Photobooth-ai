import SwiftUI

struct StylePickerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let eventId: UUID
    let capturedImageData: Data

    @State private var selecting: PhotoStyle? = nil
    @State private var uploadError: String? = nil
    @State private var queuedOffline = false
    @State private var tilesAppeared: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: BoothifySpacing.xl) {
                    // MARK: Header
                    VStack(spacing: BoothifySpacing.sm) {
                        Text("STEP 2 OF 3")
                            .font(.caption2.weight(.bold))
                            .kerning(1.6)
                            .foregroundStyle(BoothifyTheme.violet)

                        Text("Who do you want\nto be?")
                            .font(BoothifyType.displayMedium)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Pick a style — we'll handle the rest")
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, BoothifySpacing.sm)
                    .padding(.horizontal, BoothifySpacing.md)

                    // MARK: Style grid
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: BoothifySpacing.sm),
                            GridItem(.flexible(), spacing: BoothifySpacing.sm)
                        ],
                        spacing: BoothifySpacing.sm
                    ) {
                        let enabled = app.settings(for: eventId).aiPortraits.enabledStyles
                        let ordered = app.settings(for: eventId).aiPortraits.styleOrder
                            .filter { enabled.contains($0) }
                        let styles = ordered.isEmpty ? Array(enabled).sorted { $0.label < $1.label } : ordered

                        ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
                            StyleTile(
                                style: style,
                                isSelecting: selecting == style,
                                isDisabled: selecting != nil && selecting != style
                            ) {
                                pick(style: style)
                            }
                            .opacity(tilesAppeared ? 1 : 0)
                            .offset(y: tilesAppeared ? 0 : 28)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78)
                                    .delay(min(Double(index), 10) * 0.055),
                                value: tilesAppeared
                            )
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, BoothifySpacing.md)
                    .onAppear { tilesAppeared = true }

                    // Scroll clearance so content isn't hidden behind bottom bar
                    Spacer(minLength: 120)
                }
                .padding(.bottom, BoothifySpacing.xl)
            }

            // MARK: Sticky bottom bar
            VStack(spacing: 0) {
                // Fade scrim above the bar
                LinearGradient(
                    colors: [BoothifyTheme.bg.opacity(0), BoothifyTheme.bg],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 32)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Error banner — shown prominently when upload/API fails
                    if let uploadError {
                        HStack(spacing: BoothifySpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                            Text(uploadError)
                                .font(.footnote.weight(.medium))
                                .lineLimit(2)
                        }
                        .foregroundStyle(BoothifyTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BoothifySpacing.lg)
                        .padding(.vertical, BoothifySpacing.sm)
                        .background(BoothifyTheme.error.opacity(0.12))
                        .overlay(Rectangle().fill(BoothifyTheme.error.opacity(0.3)).frame(height: 1), alignment: .top)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if selecting != nil {
                                Text("Generating your portrait…")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.white)
                            } else {
                                Text("Choose a style above")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(BoothifyTheme.textSecondary)
                            }
                        }
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selecting != nil)

                        Spacer()

                        if selecting != nil {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(BoothifyTheme.violet)
                                .scaleEffect(0.9)
                        }
                    }
                    .padding(.horizontal, BoothifySpacing.lg)
                    .padding(.vertical, BoothifySpacing.md)
                }
                .background(BoothifyTheme.surface1)
                .overlay(Rectangle().fill(BoothifyTheme.surfaceLine).frame(height: 1), alignment: .top)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: uploadError != nil)
            }
        }
        .navigationTitle("Choose style")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Photo Queued", isPresented: $queuedOffline) {
            Button("OK") { app.pop() }
        } message: {
            Text("No internet connection. Your photo will be uploaded automatically when WiFi returns.")
        }
    }

    private func pick(style: PhotoStyle) {
        guard selecting == nil else { return }
        Haptics.tap(.medium)
        uploadError = nil

        // Offline path — queue locally and show confirmation.
        if !NetworkMonitor.shared.isConnected {
            let job = PendingPhotoJob(
                id: UUID(),
                eventId: eventId,
                style: style,
                imageData: capturedImageData,
                createdAt: .now
            )
            PhotoUploadQueue.shared.enqueue(job: job)
            Haptics.notify(.success)
            queuedOffline = true
            return
        }

        selecting = style

        Task {
            do {
                // 1. Upload source image, get photoId from backend.
                let photoId = try await BoothifyAPI.shared.uploadPhoto(
                    imageData: capturedImageData,
                    eventId: eventId,
                    style: style,
                )

                // 2. Fire AI generation. Don't await — ResultView will poll for status.
                Task.detached { [photoId, style] in
                    do {
                        _ = try await BoothifyAPI.shared.generatePhoto(photoId: photoId, style: style)
                    } catch {
                        // Generation errors surface through the polling response (status=failed).
                    }
                }

                // 3. Navigate to result; ResultView takes over polling.
                app.push(.result(eventId: eventId, photoId: photoId))
            } catch {
                Haptics.notify(.error)
                uploadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                selecting = nil
            }
        }
    }
}

private struct StyleTile: View {
    let style: PhotoStyle
    let isSelecting: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop — real sample photo when available, gradient placeholder otherwise.
                // New styles ship with nil previewAsset until sample images are generated.
                if let asset = style.previewAsset {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Placeholder: accent gradient + large icon — looks intentional, not broken
                    style.accentGradient
                    Image(systemName: style.iconSymbol)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Scrim for caption legibility — this is on photo media content
                LinearGradient(
                    colors: [.clear, .black.opacity(0.3), .black.opacity(0.88)],
                    startPoint: .center, endPoint: .bottom
                )

                // Caption overlay
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.label)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                    Text(style.descriptionText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(1)
                }
                .padding(BoothifySpacing.md)

                // Generating overlay
                if isSelecting {
                    ZStack {
                        Rectangle().fill(.black.opacity(0.55))
                        VStack(spacing: BoothifySpacing.sm) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.3)
                            Text("Generating…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .transition(.opacity)
                    .accessibilityLabel("Generating \(style.label)")
                }

                // Selected border highlight
                if isSelecting {
                    RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
                        .stroke(BoothifyTheme.violet, lineWidth: 2)
                        .transition(.opacity)
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
                    .stroke(
                        isSelecting ? BoothifyTheme.violet : Color.white.opacity(0.10),
                        lineWidth: isSelecting ? 2 : 1
                    )
            )
            .opacity(isDisabled ? 0.30 : 1)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelecting)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isSelecting)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.label) style. \(style.descriptionText)")
    }
}

#Preview {
    NavigationStack {
        StylePickerView(
            eventId: UUID(),
            capturedImageData: Data()
        )
    }
    .environment(AppState())
}
