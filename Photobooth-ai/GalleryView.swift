import SwiftUI

struct GalleryView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var photos: [Photo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private var event: Event? { app.event(id: eventId) }

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
    ]

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Metadata bar
                    if !photos.isEmpty {
                        HStack {
                            Text("\(photos.count) \(photos.count == 1 ? "photo" : "photos")")
                                .font(BoothifyType.captionEmphasis)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, BoothifySpacing.md)
                        .padding(.vertical, BoothifySpacing.sm)
                    }

                    // Error banner
                    if let errorMessage {
                        HStack(spacing: BoothifySpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.error)
                            Text(errorMessage)
                                .font(BoothifyType.caption)
                                .foregroundStyle(BoothifyTheme.error)
                            Spacer()
                        }
                        .padding(BoothifySpacing.md)
                        .background(BoothifyTheme.error.opacity(0.08))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(BoothifyTheme.error.opacity(0.25)),
                            alignment: .bottom
                        )
                        .padding(.bottom, BoothifySpacing.sm)
                    }

                    // Loading skeleton
                    if isLoading && photos.isEmpty {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(0..<12, id: \.self) { _ in
                                Rectangle()
                                    .fill(BoothifyTheme.surface2)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
                                    .shimmering()
                            }
                        }
                        .padding(.horizontal, BoothifySpacing.md)
                        .padding(.top, BoothifySpacing.xs)

                    // Empty state
                    } else if photos.isEmpty {
                        BoothifyEmptyState(
                            icon: "photo.stack",
                            title: "No photos yet",
                            subtitle: "Take photos via the kiosk and they'll appear here.",
                            action: {
                                Haptics.tap(.medium)
                                app.push(.camera(eventId: eventId))
                            },
                            actionLabel: "Start capturing"
                        )
                        .padding(.top, BoothifySpacing.xxl)

                    // Photo grid
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(photos) { photo in
                                Button {
                                    Haptics.tap()
                                    app.push(.result(eventId: eventId, photoId: photo.id))
                                } label: {
                                    GalleryThumbnail(photo: photo)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(photo.style.label) photo")
                            }
                        }
                        .padding(.horizontal, BoothifySpacing.md)
                        .padding(.top, BoothifySpacing.xs)
                    }
                }
                .padding(.bottom, BoothifySpacing.xxl)
            }
            .refreshable {
                await loadPhotos()
            }
        }
        .navigationTitle(event?.name ?? "Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BoothifyTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: eventId) {
            await loadPhotos()
        }
    }

    private func loadPhotos() async {
        guard let slug = event?.slug else {
            errorMessage = "Event not loaded"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let list = try await BoothifyAPI.shared.listEventPhotos(slug: slug, status: .completed, limit: 200)
            photos = list.photos
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Thumbnail

private struct GalleryThumbnail: View {
    let photo: Photo

    var body: some View {
        ZStack {
            if let url = photo.generatedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(BoothifyTheme.surface2)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(BoothifyTheme.textMuted)
                            )
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        ZStack {
                            if let asset = photo.style.previewAsset {
                                Image(asset).resizable().scaledToFill()
                            } else {
                                photo.style.accentGradient
                            }
                            Color.black.opacity(0.3)
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.error)
                        }
                    @unknown default:
                        Rectangle().fill(BoothifyTheme.surface2)
                    }
                }
            } else {
                if let asset = photo.style.previewAsset {
                    Image(asset).resizable().scaledToFill()
                } else {
                    photo.style.accentGradient
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 0.5)
        )
    }
}

// MARK: - Shimmer modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.06), location: 0.4),
                            .init(color: .white.opacity(0.12), location: 0.5),
                            .init(color: .white.opacity(0.06), location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .init(x: phase, y: 0),
                        endPoint: .init(x: phase + 1, y: 0)
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: geo.size.width * phase)
                }
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview {
    NavigationStack {
        GalleryView(eventId: UUID())
    }
    .environment(AppState())
}
